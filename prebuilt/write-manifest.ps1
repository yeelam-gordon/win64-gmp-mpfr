[CmdletBinding(DefaultParameterSetName = 'Write')]
param(
    [Parameter(ParameterSetName = 'SelfTest', Mandatory = $true)]
    [switch]$SelfTest,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [Parameter(ParameterSetName = 'Aggregate')]
    [string]$SourcesFile,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [Parameter(ParameterSetName = 'Aggregate')]
    [string]$StagingRoot,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [string]$GmpSource,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [string]$MpfrSource,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [datetime]$RunStartUtc,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [Parameter(ParameterSetName = 'Aggregate')]
    [string]$RunId,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture,

    [Parameter(ParameterSetName = 'Write')]
    [string]$Entry,

    [Parameter(ParameterSetName = 'Write')]
    [string]$MakeVariables = '',

    [Parameter(ParameterSetName = 'Write')]
    [string]$ArtifactSpec = '',

    [Parameter(ParameterSetName = 'Write')]
    [string]$CommandLog,

    [Parameter(ParameterSetName = 'Write')]
    [string]$OutputPath,

    [Parameter(ParameterSetName = 'Write')]
    [switch]$ValidateOnly,

    [Parameter(ParameterSetName = 'ValidateSources', Mandatory = $true)]
    [switch]$ValidateSourcesOnly,

    [Parameter(ParameterSetName = 'Aggregate', Mandatory = $true)]
    [switch]$Aggregate,

    [Parameter(ParameterSetName = 'Write')]
    [Parameter(ParameterSetName = 'ValidateSources')]
    [switch]$AllowDirtyOverlay
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourcesFile)) {
    $SourcesFile = Join-Path $PSScriptRoot 'sources.json'
}

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Remove-TestDirectoryReparsePoint {
    param([string]$Path, [string]$ExpectedParent)

    $fullPath = Get-FullPath $Path
    $fullExpectedParent = (Get-FullPath $ExpectedParent).TrimEnd('\')
    Assert-Condition ([string]::Equals((Split-Path -Parent $fullPath).TrimEnd('\'), $fullExpectedParent, [StringComparison]::OrdinalIgnoreCase)) "Refusing to remove a reparse fixture outside its expected parent: $fullPath"

    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $item -and $item.PSIsContainer) "Directory reparse fixture is missing: $fullPath"
    Assert-Condition ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "Refusing to remove a non-reparse fixture: $fullPath"

    [IO.Directory]::Delete($fullPath, $false)
    Assert-Condition ($null -eq (Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue)) "Unable to remove directory reparse fixture: $fullPath"
}

function Remove-TestFileReparsePoint {
    param([string]$Path, [string]$ExpectedParent)

    $fullPath = Get-FullPath $Path
    $fullExpectedParent = (Get-FullPath $ExpectedParent).TrimEnd('\')
    Assert-Condition ([string]::Equals((Split-Path -Parent $fullPath).TrimEnd('\'), $fullExpectedParent, [StringComparison]::OrdinalIgnoreCase)) "Refusing to remove a reparse fixture outside its expected parent: $fullPath"

    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $item -and -not $item.PSIsContainer) "File reparse fixture is missing: $fullPath"
    Assert-Condition ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "Refusing to remove a non-reparse fixture: $fullPath"

    [IO.File]::Delete($fullPath)
    Assert-Condition ($null -eq (Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue)) "Unable to remove file reparse fixture: $fullPath"
}

function Get-FileDigest {
    param([string]$Path, [ValidateSet('SHA256', 'SHA512')][string]$Algorithm)
    $hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    Assert-Condition ($null -ne $hasher) "Hash algorithm is unavailable: $Algorithm"
    $stream = [IO.File]::OpenRead($Path)
    try {
        $bytes = $hasher.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
    } finally {
        $stream.Dispose()
        $hasher.Dispose()
    }
}

function Get-TextDigest {
    param([string]$Text)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($hasher.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally {
        $hasher.Dispose()
    }
}

function Test-PathInside {
    param([string]$Path, [string]$Root)
    $fullPath = Get-FullPath $Path
    $fullRoot = (Get-FullPath $Root).TrimEnd('\') + '\'
    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-TreeFilesFailClosed {
    param([string]$Root, [string]$TreeName)

    $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $rootItem -and $rootItem.PSIsContainer) "$TreeName tree is missing: $Root"
    Assert-Condition (-not ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) "$TreeName tree contains a reparse point: $($rootItem.FullName)"

    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push($rootItem.FullName)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            Assert-Condition (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "$TreeName tree contains a reparse point: $($item.FullName)"
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            } else {
                $item
            }
        }
    }
}

function Resolve-TarApplicationPath {
    param($Command)

    if ($null -eq $Command) {
        $Command = Get-Command tar.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    }
    Assert-Condition ($null -ne $Command) 'tar.exe application is not available.'

    $commandType = $Command.PSObject.Properties['CommandType']
    $commandName = $Command.PSObject.Properties['Name']
    $commandSource = $Command.PSObject.Properties['Source']
    Assert-Condition ($null -ne $commandType -and ([string]$commandType.Value) -ceq 'Application') 'tar.exe must resolve to a PowerShell Application.'
    Assert-Condition ($null -ne $commandName -and ([string]$commandName.Value) -ieq 'tar.exe') 'Resolved tar application name must be tar.exe.'
    Assert-Condition ($null -ne $commandSource -and $commandSource.Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$commandSource.Value)) 'Resolved tar application has no source path.'

    $sourcePath = [string]$commandSource.Value
    Assert-Condition ([IO.Path]::IsPathRooted($sourcePath)) "Resolved tar application path is not absolute: $sourcePath"
    $fullSourcePath = Get-FullPath $sourcePath
    Assert-Condition ((Split-Path -Leaf $fullSourcePath) -ieq 'tar.exe') "Resolved tar application filename is not tar.exe: $fullSourcePath"
    $item = Get-Item -LiteralPath $fullSourcePath -Force -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $item -and -not $item.PSIsContainer) "Resolved tar application is not an existing file: $fullSourcePath"
    Assert-Condition (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "Resolved tar application is a reparse point: $fullSourcePath"
    Assert-Condition ([IO.Path]::IsPathRooted($item.FullName) -and ([IO.Path]::GetExtension($item.FullName)) -ieq '.exe') "Resolved tar application is not an absolute .exe path: $($item.FullName)"
    Assert-Condition ((Split-Path -Leaf $item.FullName) -ieq 'tar.exe') "Resolved tar application filename is not tar.exe: $($item.FullName)"

    foreach ($propertyName in @('Path', 'Definition')) {
        $property = $Command.PSObject.Properties[$propertyName]
        if ($null -eq $property) { continue }
        Assert-Condition ($property.Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) "Resolved tar application has invalid $propertyName metadata."
        $metadataPath = [string]$property.Value
        Assert-Condition ([IO.Path]::IsPathRooted($metadataPath)) "Resolved tar application $propertyName path is not absolute: $metadataPath"
        Assert-Condition ([string]::Equals((Get-FullPath $metadataPath), $item.FullName, [StringComparison]::OrdinalIgnoreCase)) "Resolved tar application metadata paths disagree."
    }

    return $item.FullName
}

function Resolve-GitApplicationPath {
    param($Command)

    if ($null -eq $Command) {
        $Command = Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    }
    Assert-Condition ($null -ne $Command) 'git.exe application is not available.'

    $commandType = $Command.PSObject.Properties['CommandType']
    $commandName = $Command.PSObject.Properties['Name']
    $commandSource = $Command.PSObject.Properties['Source']
    Assert-Condition ($null -ne $commandType -and ([string]$commandType.Value) -ceq 'Application') 'git.exe must resolve to a PowerShell Application.'
    Assert-Condition ($null -ne $commandName -and ([string]$commandName.Value) -ieq 'git.exe') 'Resolved Git application name must be git.exe.'
    Assert-Condition ($null -ne $commandSource -and $commandSource.Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$commandSource.Value)) 'Resolved Git application has no source path.'

    $sourcePath = [string]$commandSource.Value
    Assert-Condition ([IO.Path]::IsPathRooted($sourcePath)) "Resolved Git application path is not absolute: $sourcePath"
    $fullSourcePath = Get-FullPath $sourcePath
    Assert-Condition ((Split-Path -Leaf $fullSourcePath) -ieq 'git.exe') "Resolved Git application filename is not git.exe: $fullSourcePath"
    $item = Get-Item -LiteralPath $fullSourcePath -Force -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $item -and -not $item.PSIsContainer) "Resolved Git application is not an existing file: $fullSourcePath"
    Assert-Condition (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) "Resolved Git application is a reparse point: $fullSourcePath"
    Assert-Condition ([IO.Path]::IsPathRooted($item.FullName) -and ([IO.Path]::GetExtension($item.FullName)) -ieq '.exe') "Resolved Git application is not an absolute .exe path: $($item.FullName)"
    Assert-Condition ((Split-Path -Leaf $item.FullName) -ieq 'git.exe') "Resolved Git application filename is not git.exe: $($item.FullName)"

    foreach ($propertyName in @('Path', 'Definition')) {
        $property = $Command.PSObject.Properties[$propertyName]
        if ($null -eq $property) { continue }
        Assert-Condition ($property.Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) "Resolved Git application has invalid $propertyName metadata."
        $metadataPath = [string]$property.Value
        Assert-Condition ([IO.Path]::IsPathRooted($metadataPath)) "Resolved Git application $propertyName path is not absolute: $metadataPath"
        Assert-Condition ([string]::Equals((Get-FullPath $metadataPath), $item.FullName, [StringComparison]::OrdinalIgnoreCase)) "Resolved Git application metadata paths disagree."
    }

    return $item.FullName
}

function Assert-ArchiveMembersSafe {
    param([string]$TarPath, [string]$ArchivePath, [string]$ExtractionRoot)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $TarPath
    $startInfo.Arguments = '-tf "' + $ArchivePath.Replace('"', '\"') + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        Assert-Condition $process.Start() "Unable to list archive members: $ArchivePath"
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        Assert-Condition ($process.ExitCode -eq 0) "Archive member listing failed: $stderr"
        Assert-Condition ([string]::IsNullOrWhiteSpace($stderr)) "Archive member listing produced diagnostics: $stderr"
    } finally {
        $process.Dispose()
    }

    $listing = $stdout.TrimEnd("`r", "`n")
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($listing)) 'Archive contains no members.'
    foreach ($member in @($listing -split "`r`n|`n|`r")) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($member)) 'Archive contains an empty or malformed member path.'
        Assert-Condition ($member -notmatch '[\x00-\x1f\x7f]') "Archive member path contains control characters: $member"
        Assert-Condition ($member -notmatch '^[\\/]') "Archive member path is absolute: $member"
        Assert-Condition ($member -notmatch '^[A-Za-z]:') "Archive member path is drive-qualified: $member"
        Assert-Condition ($member -notmatch ':') "Archive member path contains a Windows drive or stream qualifier: $member"
        Assert-Condition ($member -notmatch '[\\/]{2}') "Archive member path contains an empty segment: $member"

        $trimmedMember = $member.TrimEnd([char[]]@('\', '/'))
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($trimmedMember)) "Archive member path is malformed: $member"
        $segments = @($trimmedMember -split '[\\/]')
        Assert-Condition (-not ($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' })) "Archive member path contains an unsafe segment: $member"

        try {
            $candidate = Get-FullPath (Join-Path $ExtractionRoot ($trimmedMember -replace '/', '\'))
        } catch {
            throw "Archive member path is malformed: $member"
        }
        Assert-Condition (Test-PathInside $candidate $ExtractionRoot) "Archive member path escapes extraction root: $member"
    }
}

function Expand-ArchiveWithTar {
    param([string]$TarPath, [string]$ArchivePath, [string]$ExtractionRoot, [string]$Name)

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $TarPath
    $startInfo.Arguments = '-xf "' + $ArchivePath.Replace('"', '\"') + '" -C "' + $ExtractionRoot.Replace('"', '\"') + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        Assert-Condition $process.Start() "Unable to extract $Name archive: $ArchivePath"
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        Assert-Condition ($process.ExitCode -eq 0) "$Name archive extraction failed: $stderr"
        Assert-Condition ([string]::IsNullOrWhiteSpace($stderr)) "$Name archive extraction produced diagnostics: $stderr"
        Assert-Condition ([string]::IsNullOrWhiteSpace($stdout)) "$Name archive extraction produced unexpected output: $stdout"
    } finally {
        $process.Dispose()
    }
}

function Read-SourceLock {
    param([string]$Path)
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Source lock does not exist: $Path"
    $lock = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    Assert-Condition ($lock.schemaVersion -eq 1) 'Unsupported sources.json schemaVersion.'
    foreach ($name in @('gmp', 'mpfr')) {
        $item = $lock.$name
        Assert-Condition ($null -ne $item) "Missing '$name' source metadata."
        $values = @{}
        foreach ($field in @('version', 'url', 'archive', 'sha512', 'extractedDirectory', 'identityFile')) {
            $property = $item.PSObject.Properties[$field]
            Assert-Condition ($null -ne $property -and $null -ne $property.Value) "$name $field is missing."
            Assert-Condition ($property.Value -is [string]) "$name $field must be a string."
            $value = [string]$property.Value
            Assert-Condition (-not [string]::IsNullOrWhiteSpace($value)) "$name $field is blank."
            $values[$field] = $value
        }

        Assert-Condition ($values.version -match '^[0-9]+(?:\.[0-9]+)+(?:[-+._][0-9A-Za-z]+)*$') "$name version is invalid."

        $url = $null
        Assert-Condition ([uri]::TryCreate($values.url, [UriKind]::Absolute, [ref]$url)) "$name URL is invalid."
        Assert-Condition ($url.Scheme -ceq [Uri]::UriSchemeHttps) "$name URL must use HTTPS."
        Assert-Condition ([string]::IsNullOrEmpty($url.UserInfo) -and [string]::IsNullOrEmpty($url.Fragment)) "$name URL is invalid."
        Assert-Condition ($values.url -notmatch '(?i)latest|current') "$name URL must be immutable."

        Assert-Condition (
            -not [IO.Path]::IsPathRooted($values.archive) -and
            $values.archive -ceq [IO.Path]::GetFileName($values.archive) -and
            $values.archive -notmatch '[\x00-\x1f<>:"/\\|?*]'
        ) "$name archive filename is invalid."
        $urlArchive = [Uri]::UnescapeDataString($url.Segments[$url.Segments.Length - 1])
        Assert-Condition ($urlArchive -ceq $values.archive) "$name URL archive filename does not match archive."
        Assert-Condition ($values.sha512 -match '^[0-9a-fA-F]{128}$') "$name SHA-512 is invalid."
        Assert-Condition (
            -not [IO.Path]::IsPathRooted($values.extractedDirectory) -and
            $values.extractedDirectory -ceq [IO.Path]::GetFileName($values.extractedDirectory) -and
            $values.extractedDirectory -notmatch '^(?:\.|\.\.)$|[\x00-\x1f<>:"/\\|?*]'
        ) "$name extracted directory is invalid."
        Assert-Condition (
            -not [IO.Path]::IsPathRooted($values.identityFile) -and
            $values.identityFile -notmatch '(^|[\\/])\.\.?([\\/]|$)|[\\/]{2}|[\\/]$|[\x00-\x1f<>:"|?*]'
        ) "$name identity file is invalid."

        $identityRegexProperty = $item.PSObject.Properties['identityRegex']
        if ($null -ne $identityRegexProperty -and -not [string]::IsNullOrWhiteSpace([string]$identityRegexProperty.Value)) {
            try {
                [void][regex]::new([string]$identityRegexProperty.Value)
            } catch {
                throw "$name identity regex is invalid."
            }
        }
    }
    return $lock
}

function Assert-TreeMatches {
    param(
        [string]$ReferenceRoot,
        [string]$CandidateRoot,
        [string[]]$AllowedCandidatePrefixes = @()
    )
    $referenceFiles = @{}
    foreach ($file in Get-TreeFilesFailClosed $ReferenceRoot 'Reference') {
        $relative = $file.FullName.Substring($ReferenceRoot.TrimEnd('\').Length + 1)
        $referenceFiles[$relative.ToLowerInvariant()] = [ordered]@{
            path = $relative
            sha256 = Get-FileDigest $file.FullName SHA256
        }
    }
    $candidateFiles = @{}
    foreach ($file in Get-TreeFilesFailClosed $CandidateRoot 'Candidate') {
        $relative = $file.FullName.Substring($CandidateRoot.TrimEnd('\').Length + 1)
        $candidateFiles[$relative.ToLowerInvariant()] = [ordered]@{
            path = $relative
            sha256 = Get-FileDigest $file.FullName SHA256
        }
    }
    foreach ($key in $referenceFiles.Keys) {
        Assert-Condition ($candidateFiles.ContainsKey($key)) "Extracted source is missing locked file: $($referenceFiles[$key].path)"
        Assert-Condition ($candidateFiles[$key].sha256 -ceq $referenceFiles[$key].sha256) "Extracted source differs from locked archive: $($referenceFiles[$key].path)"
    }
    foreach ($key in $candidateFiles.Keys) {
        if ($referenceFiles.ContainsKey($key)) { continue }
        $allowed = $false
        foreach ($prefix in $AllowedCandidatePrefixes) {
            if ($candidateFiles[$key].path.StartsWith($prefix.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $allowed = $true
                break
            }
        }
        Assert-Condition $allowed "Extracted source contains an unlocked file: $($candidateFiles[$key].path)"
    }
    $identityLines = @($referenceFiles.Values | Sort-Object path | ForEach-Object { "$($_.path)=$($_.sha256)" })
    return [ordered]@{
        fileCount = $referenceFiles.Count
        treeSha256 = Get-TextDigest ($identityLines -join "`n")
    }
}

function Get-SourceRecord {
    param(
        [string]$Name,
        $Metadata,
        [string]$SourcePath,
        [string]$OverlayPath,
        [string]$ValidationRoot
    )
    $version = [string]$Metadata.version
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($version)) "$Name version is required."
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($SourcePath)) "$Name source path is required."
    $source = Get-FullPath $SourcePath
    Assert-Condition (Test-Path -LiteralPath $source -PathType Container) "$Name source directory does not exist: $source"
    Assert-Condition ((Split-Path -Leaf $source) -ceq [string]$Metadata.extractedDirectory) "$Name source directory must be named '$($Metadata.extractedDirectory)'."
    $identity = Join-Path $source ([string]$Metadata.identityFile)
    Assert-Condition (Test-Path -LiteralPath $identity -PathType Leaf) "$Name extracted-source identity file is missing: $identity"
    $identityText = Get-Content -LiteralPath $identity -Raw
    $identityRegex = ''
    $identityRegexProperty = $Metadata.PSObject.Properties['identityRegex']
    if ($null -ne $identityRegexProperty) { $identityRegex = [string]$identityRegexProperty.Value }
    if ([string]::IsNullOrWhiteSpace($identityRegex)) {
        $identityRegex = [regex]::Escape($version)
    }
    try {
        $identityPattern = [regex]::new($identityRegex)
    } catch {
        throw "$Name identity regex is invalid."
    }
    Assert-Condition ($identityPattern.IsMatch($identityText)) "$Name identity file does not match version $version."

    $archive = Join-Path (Split-Path -Parent $source) ([string]$Metadata.archive)
    Assert-Condition (Test-Path -LiteralPath $archive -PathType Leaf) "$Name canonical archive is required beside the source directory: $archive"
    $actualHash = Get-FileDigest $archive SHA512
    Assert-Condition ($actualHash -ceq ([string]$Metadata.sha512).ToLowerInvariant()) "$Name archive SHA-512 does not match sources.json."
    Assert-Condition (Test-Path -LiteralPath $OverlayPath -PathType Container) "$Name repository overlay is missing: $OverlayPath"

    $validation = Join-Path $ValidationRoot ("source-validation-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $validation | Out-Null
    try {
        $tarPath = Resolve-TarApplicationPath
        Assert-ArchiveMembersSafe $tarPath $archive $validation
        Expand-ArchiveWithTar $tarPath $archive $validation $Name
        $lockedSource = Join-Path $validation ([string]$Metadata.extractedDirectory)
        $sourceIdentity = Assert-TreeMatches $lockedSource $source @('win64')
        $overlayIdentity = Assert-TreeMatches $OverlayPath (Join-Path $source 'win64')
    } finally {
        if (Test-Path -LiteralPath $validation) { Remove-Item -LiteralPath $validation -Recurse -Force }
    }

    [ordered]@{
        name = $Name
        version = [string]$Metadata.version
        url = [string]$Metadata.url
        archive = [string]$Metadata.archive
        archiveSha512 = $actualHash
        extractedDirectory = [string]$Metadata.extractedDirectory
        extractedSource = $source
        extractedFileCount = $sourceIdentity.fileCount
        extractedTreeSha256 = $sourceIdentity.treeSha256
        identityFile = [string]$Metadata.identityFile
        identitySha256 = Get-FileDigest $identity SHA256
        appliedOverlayFileCount = $overlayIdentity.fileCount
        appliedOverlayTreeSha256 = $overlayIdentity.treeSha256
    }
}

function Get-OverlayRecord {
    param([string]$RepositoryRoot, [bool]$AllowDirty)
    $gitPath = Resolve-GitApplicationPath
    $commitOutput = @(& $gitPath -C $RepositoryRoot rev-parse HEAD)
    $commitExitCode = $LASTEXITCODE
    Assert-Condition ($commitExitCode -eq 0) 'Unable to identify overlay Git commit.'
    $commit = ($commitOutput -join "`n").Trim()
    Assert-Condition ($commit -match '^[0-9a-f]{40}$') 'Unable to identify overlay Git commit.'
    $status = @(& $gitPath -C $RepositoryRoot status --porcelain)
    $statusExitCode = $LASTEXITCODE
    Assert-Condition ($statusExitCode -eq 0) 'Unable to determine overlay dirty state.'
    $dirty = $status.Count -gt 0
    Assert-Condition ($AllowDirty -or -not $dirty) 'Overlay repository is dirty; commit the five-file change or pass --allow-dirty-overlay for development evidence.'

    $files = @()
    foreach ($overlayRoot in @(
        [ordered]@{ name = 'GMP'; relativePath = 'libgmp\win64' },
        [ordered]@{ name = 'MPFR'; relativePath = 'libmpfr\win64' }
    )) {
        $root = Join-Path $RepositoryRoot $overlayRoot.relativePath
        Assert-Condition (Test-Path -LiteralPath $root -PathType Container) "Required $($overlayRoot.name) overlay directory is missing: $root. Restore the overlay at '$($overlayRoot.relativePath)' before writing the manifest."
        foreach ($file in Get-TreeFilesFailClosed $root "$($overlayRoot.name) overlay" | Sort-Object FullName) {
            $relative = $file.FullName.Substring($RepositoryRoot.TrimEnd('\').Length + 1)
            $files += [ordered]@{
                path = $relative
                sha256 = Get-FileDigest $file.FullName SHA256
            }
        }
    }
    [ordered]@{
        commit = $commit
        dirty = $dirty
        inputs = $files
    }
}

function Get-ToolRecord {
    param([string]$Name, [bool]$Required)
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        Assert-Condition (-not $Required) "Required build tool is not available: $Name"
        return $null
    }
    $text = ''
    try {
        $text = ((& $command.Source 2>&1 | Select-Object -First 8) -join "`n").Trim()
    } catch {
        $text = $_.Exception.Message
    }
    [ordered]@{ name = $Name; path = $command.Source; version = $text }
}

function Get-MachineFromBytes {
    param([byte[]]$Bytes, [string]$Path)
    Assert-Condition ($Bytes.Length -ge 2) "Artifact is too small to contain a COFF header: $Path"
    if ($Bytes.Length -ge 64 -and $Bytes[0] -eq 0x4d -and $Bytes[1] -eq 0x5a) {
        $peOffset = [BitConverter]::ToInt32($Bytes, 0x3c)
        Assert-Condition ($peOffset -ge 0 -and $peOffset + 6 -le $Bytes.Length) "Invalid PE header offset: $Path"
        Assert-Condition ($Bytes[$peOffset] -eq 0x50 -and $Bytes[$peOffset + 1] -eq 0x45 -and $Bytes[$peOffset + 2] -eq 0 -and $Bytes[$peOffset + 3] -eq 0) "Invalid PE signature: $Path"
        return ('{0:X4}' -f [BitConverter]::ToUInt16($Bytes, $peOffset + 4))
    }
    return ('{0:X4}' -f [BitConverter]::ToUInt16($Bytes, 0))
}

function Get-LibraryDetails {
    param([byte[]]$Bytes, [string]$Path)
    $signature = [Text.Encoding]::ASCII.GetString($Bytes, 0, [Math]::Min(8, $Bytes.Length))
    Assert-Condition ($signature -ceq "!<arch>`n") "Invalid COFF library signature: $Path"
    $offset = 8
    $machines = @()
    $hasImportObject = $false
    while ($offset + 60 -le $Bytes.Length) {
        $sizeText = [Text.Encoding]::ASCII.GetString($Bytes, $offset + 48, 10).Trim()
        $memberSize = 0
        Assert-Condition ([int]::TryParse($sizeText, [ref]$memberSize)) "Invalid COFF library member size: $Path"
        $dataOffset = $offset + 60
        Assert-Condition ($dataOffset + $memberSize -le $Bytes.Length) "Truncated COFF library member: $Path"
        if ($memberSize -ge 8) {
            $sig1 = [BitConverter]::ToUInt16($Bytes, $dataOffset)
            $sig2 = [BitConverter]::ToUInt16($Bytes, $dataOffset + 2)
            if ($sig1 -eq 0 -and $sig2 -eq 0xffff) {
                $machines += ('{0:X4}' -f [BitConverter]::ToUInt16($Bytes, $dataOffset + 6))
                $hasImportObject = $true
            } elseif ($sig1 -eq 0x8664 -or $sig1 -eq 0xaa64) {
                $machines += ('{0:X4}' -f $sig1)
            }
        }
        $offset = $dataOffset + $memberSize
        if (($offset % 2) -ne 0) { $offset++ }
    }
    $uniqueMachines = @($machines | Select-Object -Unique)
    Assert-Condition ($uniqueMachines.Count -eq 1) "Library must contain exactly one recognized machine type: $Path"
    [ordered]@{
        machine = $uniqueMachines[0]
        classification = $(if ($hasImportObject) { 'import' } else { 'static' })
    }
}

function Get-ArtifactRecord {
    param(
        [string]$Spec,
        [string]$Root,
        [datetime]$Started,
        [string]$CurrentEntry
    )
    $parts = @($Spec -split '\|', 5)
    Assert-Condition ($parts.Count -ge 4) "Artifact spec must be relative-path|library|class|machine[|sha256]: $Spec"
    $relativePath, $library, $declaredClass, $declaredMachine = $parts[0..3]
    Assert-Condition ($library -in @('gmp', 'mpfr', 'fixture')) "Unknown artifact library: $library"
    Assert-Condition ($declaredClass -in @('static', 'import', 'dll', 'object')) "Unknown artifact class: $declaredClass"
    Assert-Condition ($declaredMachine.ToUpperInvariant() -in @('8664', 'AA64')) "Unknown declared machine: $declaredMachine"
    Assert-Condition (-not [IO.Path]::IsPathRooted($relativePath)) "Artifact path must be relative to staging: $relativePath"
    $path = Get-FullPath (Join-Path $Root $relativePath)
    Assert-Condition (Test-PathInside $path $Root) "Artifact is outside staging root: $path"
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Artifact is missing: $path"
    $file = Get-Item -LiteralPath $path
    Assert-Condition ($file.Length -gt 0) "Artifact is empty: $path"
    Assert-Condition ($file.LastWriteTimeUtc -ge $Started.ToUniversalTime()) "Artifact predates the current run: $path"
    Assert-Condition (-not ($CurrentEntry -match '(?i)full64bit' -and $library -eq 'mpfr')) 'MPFR artifacts are forbidden in FULL_64BIT entries.'

    [byte[]]$bytes = [IO.File]::ReadAllBytes($path)
    if ($declaredClass -eq 'dll') {
        Assert-Condition ([IO.Path]::GetExtension($path) -ieq '.dll') "DLL classification requires a .dll artifact: $path"
        $actualMachine = Get-MachineFromBytes $bytes $path
        $actualClass = 'dll'
    } elseif ($declaredClass -eq 'object') {
        Assert-Condition ([IO.Path]::GetExtension($path) -in @('.obj', '.o')) "Object classification requires an object artifact: $path"
        $actualMachine = Get-MachineFromBytes $bytes $path
        $actualClass = 'object'
    } else {
        Assert-Condition ([IO.Path]::GetExtension($path) -ieq '.lib') "Library classification requires a .lib artifact: $path"
        $details = Get-LibraryDetails $bytes $path
        $actualMachine = $details.machine
        $actualClass = $details.classification
    }
    Assert-Condition ($actualMachine -ceq $declaredMachine.ToUpperInvariant()) "Wrong artifact machine for ${relativePath}: expected $declaredMachine, found $actualMachine."
    Assert-Condition ($actualClass -ceq $declaredClass) "Wrong artifact class for ${relativePath}: expected $declaredClass, found $actualClass."
    $sha256 = Get-FileDigest $path SHA256
    if ($parts.Count -eq 5 -and -not [string]::IsNullOrWhiteSpace($parts[4])) {
        Assert-Condition ($sha256 -ceq $parts[4].ToLowerInvariant()) "Wrong declared SHA-256 for $relativePath."
    }
    [ordered]@{
        path = $relativePath
        library = $library
        classification = $actualClass
        machine = $actualMachine
        size = $file.Length
        sha256 = $sha256
        lastWriteUtc = $file.LastWriteTimeUtc.ToString('o')
    }
}

function Get-CommandRecords {
    param([string]$Path, [string]$Root, [datetime]$Started)
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Path)) 'Command log is required.'
    $fullPath = Get-FullPath $Path
    Assert-Condition (Test-PathInside $fullPath $Root) 'Command log must be inside staging root.'
    Assert-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "Command log is missing: $fullPath"
    Assert-Condition ((Get-Item -LiteralPath $fullPath).LastWriteTimeUtc -ge $Started.ToUniversalTime()) 'Command log predates the current run.'
    $records = @()
    foreach ($line in Get-Content -LiteralPath $fullPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = @($line -split '\|', 7)
        Assert-Condition ($parts.Count -eq 7) "Malformed command log record: $line"
        $exitCode = 0
        Assert-Condition ([int]::TryParse($parts[4], [ref]$exitCode)) "Malformed command exit code: $line"
        $timestamp = [datetimeoffset]::MinValue
        Assert-Condition ([datetimeoffset]::TryParse($parts[0], [ref]$timestamp)) "Malformed command timestamp: $line"
        Assert-Condition ($timestamp.UtcDateTime -ge $Started.ToUniversalTime()) "Command timestamp predates run start: $line"
        Assert-Condition ($timestamp.UtcDateTime -le [datetime]::UtcNow.AddMinutes(5)) "Command timestamp is in the future: $line"
        Assert-Condition (-not [IO.Path]::IsPathRooted($parts[5])) "Command log path must be relative: $line"
        $recordLog = Get-FullPath (Join-Path $Root $parts[5])
        Assert-Condition (Test-PathInside $recordLog $Root) "Command output log is outside staging: $line"
        Assert-Condition (Test-Path -LiteralPath $recordLog -PathType Leaf) "Command output log is missing: $recordLog"
        $recordLogItem = Get-Item -LiteralPath $recordLog
        Assert-Condition ($recordLogItem.LastWriteTimeUtc -ge $Started.ToUniversalTime()) "Command output log predates the run: $recordLog"
        $records += [ordered]@{
            timestamp = $parts[0]
            entry = $parts[1]
            action = $parts[2]
            library = $(if ($parts[3] -eq '-') { $null } else { $parts[3] })
            exitCode = $exitCode
            log = $parts[5]
            command = $parts[6]
        }
    }
    return $records
}

function Test-IsTrustedNMakeCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    $executable = [regex]::Match($Command, '^\s*(?:"(?<quoted>[^"]+)"|(?<unquoted>\S+))(?=\s|$)')
    if (-not $executable.Success) { return $false }
    $path = $(if ($executable.Groups['quoted'].Success) {
        $executable.Groups['quoted'].Value
    } else {
        $executable.Groups['unquoted'].Value
    })
    $isAbsoluteWindowsPath = $path -match '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+\\)'
    return $isAbsoluteWindowsPath -and ([IO.Path]::GetFileName($path) -ieq 'nmake.exe')
}

function Remove-AnsiTerminalControlSequences {
    param([string]$Text)
    if ($null -eq $Text) { return $null }
    return [regex]::Replace($Text, '(?:\x1B\[|\x9B)[0-?]*[ -/]*[@-~]', ' ')
}

function Assert-NativeTestEvidence {
    param($Records, [string]$Library, [string]$CurrentEntry, [string]$Root)
    $matches = @($Records | Where-Object {
        $_.entry -ceq $CurrentEntry -and
        $_.action -ceq 'build-check' -and
        $_.library -ceq $Library -and
        $_.exitCode -eq 0 -and
        (Test-IsTrustedNMakeCommand $_.command) -and
        $_.command -match '(?i)(?:^|\s)check(?:\s|$)'
    })
    Assert-Condition ($matches.Count -eq 1) "Exactly one successful structured check record is required for $Library in entry '$CurrentEntry'."
    $logPath = Get-FullPath (Join-Path $Root $matches[0].log)
    Assert-Condition ((Get-Item -LiteralPath $logPath).Length -gt 0) "Check log is empty for $Library."
    $logText = Get-Content -LiteralPath $logPath -Raw
    $parsedLogText = Remove-AnsiTerminalControlSequences $logText
    Assert-Condition ($parsedLogText -match '(?im)\bPASS(?:ED)?\b') "Check log does not contain passing test evidence for $Library."
    $summaryLines = @($parsedLogText -split "\r?\n" | Where-Object {
        $_ -match '(?i)\boverall\b' -and
        $_ -match '(?i)\bsucceeded\b' -and
        $_ -match '(?i)\bfailed\b' -and
        $_ -match '(?i)\bskipped\b'
    })
    Assert-Condition ($summaryLines.Count -eq 1) "Exactly one test-suite summary is required for $Library."
    $summary = [regex]::Match(
        $summaryLines[0],
        '^\s*(?<overall>\d+)\s+overall\s*,\s*(?<succeeded>\d+)\s+succeeded\s*,\s*(?<failed>\d+)\s+failed\s*,\s*(?<skipped>\d+)\s+skipped\s*\.\s*$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    Assert-Condition ($summary.Success) "Malformed test-suite summary for $Library."
    $counts = @{}
    foreach ($name in @('overall', 'succeeded', 'failed', 'skipped')) {
        $value = 0L
        Assert-Condition ([long]::TryParse($summary.Groups[$name].Value, [ref]$value)) "Invalid $name test count for $Library."
        Assert-Condition ($value -ge 0) "Negative $name test count for $Library."
        $counts[$name] = $value
    }
    Assert-Condition ([decimal]$counts.overall -eq ([decimal]$counts.succeeded + [decimal]$counts.failed + [decimal]$counts.skipped)) "Inconsistent test-suite summary for $Library."
    Assert-Condition ($counts.succeeded -gt 0) "Test-suite summary reports no successful tests for $Library."
    Assert-Condition ($counts.failed -eq 0) "Test-suite summary reports failed tests for $Library."
}

function ConvertTo-SupportedArchitecture {
    param([string]$Architecture)
    if ([string]::IsNullOrWhiteSpace($Architecture)) { return $null }
    switch ($Architecture.Trim().ToLowerInvariant()) {
        'x64' { return 'x64' }
        'arm64' { return 'arm64' }
        default { return $null }
    }
}

function Get-NativeOSArchitecture {
    try {
        return ConvertTo-SupportedArchitecture ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString())
    } catch {
        return $null
    }
}

function Test-IsNative {
    param([string]$Target, [string]$NativeArchitecture = (Get-NativeOSArchitecture))
    $targetArchitecture = ConvertTo-SupportedArchitecture $Target
    $hostArchitecture = ConvertTo-SupportedArchitecture $NativeArchitecture
    return $null -ne $targetArchitecture -and $targetArchitecture -ceq $hostArchitecture
}

function Get-ExecutionLimitation {
    param([string]$Target, [string]$NativeArchitecture, [bool]$NativeExecution)
    if ($NativeExecution) {
        return 'Native tests were run by the selected Makefile check target.'
    }
    return "Target architecture $Target differs from host/native architecture $NativeArchitecture; native runtime tests were not run."
}

function ConvertTo-ConciseDiagnosticText {
    param([string]$Text, [int]$MaximumLength = 500)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $concise = ($Text -replace '\s+', ' ').Trim()
    if ($concise.Length -le $MaximumLength) { return $concise }
    return $concise.Substring(0, $MaximumLength - 3) + '...'
}

function Format-ErrorRecordDiagnostic {
    param([Management.Automation.ErrorRecord]$ErrorRecord)
    $parts = @("write-manifest failed: $(ConvertTo-ConciseDiagnosticText $ErrorRecord.Exception.Message)")

    $category = [string]$ErrorRecord.CategoryInfo.Category
    $target = ConvertTo-ConciseDiagnosticText ([string]$ErrorRecord.CategoryInfo.TargetName) 200
    if (-not [string]::IsNullOrWhiteSpace($category)) {
        $parts += $(if ($null -ne $target) { "Category=$category; Target=$target" } else { "Category=$category" })
    }

    $stack = ConvertTo-ConciseDiagnosticText $ErrorRecord.ScriptStackTrace 500
    if ($null -ne $stack) {
        $parts += "ScriptStack=$stack"
    } elseif ($null -ne $ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.ScriptLineNumber -gt 0) {
        $scriptName = ConvertTo-ConciseDiagnosticText $ErrorRecord.InvocationInfo.ScriptName 300
        $parts += "Location=${scriptName}:$($ErrorRecord.InvocationInfo.ScriptLineNumber)"
    }

    $innerMessages = @()
    $inner = $ErrorRecord.Exception.InnerException
    while ($null -ne $inner -and $innerMessages.Count -lt 5) {
        $innerMessage = ConvertTo-ConciseDiagnosticText $inner.Message
        if ($null -ne $innerMessage) { $innerMessages += $innerMessage }
        $inner = $inner.InnerException
    }
    if ($innerMessages.Count -gt 0) { $parts += "Inner=$($innerMessages -join ' -> ')" }
    return $parts -join ' | '
}

function Invoke-ExpectedFailure {
    param([scriptblock]$Action, [string]$Name, [string]$ExpectedMessage)
    $failed = $false
    try {
        & $Action
    } catch {
        $failed = $true
        if (-not [string]::IsNullOrWhiteSpace($ExpectedMessage)) {
            Assert-Condition $_.Exception.Message.Contains($ExpectedMessage) "Self-test '$Name' failed for the wrong reason: $($_.Exception.Message)"
        }
    }
    Assert-Condition $failed "Self-test '$Name' did not fail closed."
}

function New-CoffObject {
    param([string]$Path, [UInt16]$Machine)
    $bytes = New-Object byte[] 20
    [BitConverter]::GetBytes($Machine).CopyTo($bytes, 0)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function New-TestTarArchive {
    param([string]$Path, [string]$MemberPath, [string]$Content)
    $encoding = [Text.Encoding]::ASCII
    $nameBytes = $encoding.GetBytes($MemberPath)
    Assert-Condition ($nameBytes.Length -le 100) 'Self-test tar member name is too long.'
    $contentBytes = $encoding.GetBytes($Content)
    $header = New-Object byte[] 512
    [Array]::Copy($nameBytes, 0, $header, 0, $nameBytes.Length)

    foreach ($field in @(
        @(100, 8, '0000644'),
        @(108, 8, '0000000'),
        @(116, 8, '0000000'),
        @(124, 12, ([Convert]::ToString($contentBytes.Length, 8).PadLeft(11, '0'))),
        @(136, 12, '00000000000')
    )) {
        $bytes = $encoding.GetBytes(([string]$field[2]) + [char]0)
        [Array]::Copy($bytes, 0, $header, [int]$field[0], [Math]::Min($bytes.Length, [int]$field[1]))
    }
    for ($index = 148; $index -lt 156; $index++) { $header[$index] = 0x20 }
    $header[156] = [byte][char]'0'
    [Array]::Copy($encoding.GetBytes("ustar" + [char]0 + '00'), 0, $header, 257, 8)
    $checksum = 0
    foreach ($value in $header) { $checksum += $value }
    $checksumBytes = $encoding.GetBytes(([Convert]::ToString($checksum, 8).PadLeft(6, '0')) + [char]0 + ' ')
    [Array]::Copy($checksumBytes, 0, $header, 148, 8)

    $stream = [IO.File]::Create($Path)
    try {
        $stream.Write($header, 0, $header.Length)
        $stream.Write($contentBytes, 0, $contentBytes.Length)
        $padding = (512 - ($contentBytes.Length % 512)) % 512
        if ($padding -gt 0) { $stream.Write((New-Object byte[] $padding), 0, $padding) }
        $stream.Write((New-Object byte[] 1024), 0, 1024)
    } finally {
        $stream.Dispose()
    }
}

function Invoke-SelfTest {
    $work = Join-Path $PSScriptRoot '.test-work\manifest-self-test'
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $started = [datetime]::UtcNow.AddSeconds(-1)
        $x64 = Join-Path $work 'x64.obj'
        $arm64 = Join-Path $work 'arm64.obj'
        New-CoffObject $x64 0x8664
        New-CoffObject $arm64 0xaa64
        $x64Record = Get-ArtifactRecord 'x64.obj|fixture|object|8664' $work $started 'self-test'
        $armRecord = Get-ArtifactRecord 'arm64.obj|fixture|object|AA64' $work $started 'self-test'
        Assert-Condition ($x64Record.machine -eq '8664') 'x64 machine detection failed.'
        Assert-Condition ($armRecord.machine -eq 'AA64') 'Arm64 machine detection failed.'
        Assert-Condition (Test-IsNative 'x64' 'x64') 'x64 target/host native match failed.'
        Assert-Condition (Test-IsNative 'arm64' 'arm64') 'Arm64 target/host native match failed.'
        Assert-Condition (-not (Test-IsNative 'x64' 'arm64')) 'x64 target was incorrectly native on an Arm64 host.'
        Assert-Condition (-not (Test-IsNative 'arm64' 'x64')) 'Arm64 target was incorrectly native on an x64 host.'
        Assert-Condition (-not (Test-IsNative 'x64' 'unknown')) 'Unknown host architecture did not fail closed.'
        Assert-Condition (-not (Test-IsNative 'unknown' 'x64')) 'Unknown target architecture did not fail closed.'
        Assert-Condition ((Get-ExecutionLimitation 'x64' 'ARM64' $false) -ceq 'Target architecture x64 differs from host/native architecture ARM64; native runtime tests were not run.') 'x64 non-native limitation text is inaccurate.'
        Assert-Condition ((Get-ExecutionLimitation 'arm64' 'AMD64' $false) -ceq 'Target architecture arm64 differs from host/native architecture AMD64; native runtime tests were not run.') 'Arm64 non-native limitation text is inaccurate.'
        Assert-Condition ((Get-ExecutionLimitation 'x64' 'AMD64' $true) -ceq 'Native tests were run by the selected Makefile check target.') 'Native limitation text changed unexpectedly.'

        $diagnosticException = New-Object ApplicationException(
            "outer diagnostic failure`nwith detail",
            (New-Object InvalidOperationException('inner diagnostic cause'))
        )
        $diagnosticRecord = New-Object Management.Automation.ErrorRecord(
            $diagnosticException,
            'ManifestSelfTestFailure',
            [Management.Automation.ErrorCategory]::InvalidData,
            'fixture-target'
        )
        $diagnostic = Format-ErrorRecordDiagnostic $diagnosticRecord
        Assert-Condition ($diagnostic.Contains('write-manifest failed: outer diagnostic failure with detail')) 'Error diagnostic omitted or failed to normalize the exception message.'
        Assert-Condition ($diagnostic.Contains('Category=InvalidData; Target=fixture-target')) 'Error diagnostic omitted category or target context.'
        Assert-Condition ($diagnostic.Contains('Inner=inner diagnostic cause')) 'Error diagnostic omitted the inner exception chain.'

        $sourceLockPath = Join-Path $work 'sources.json'
        $validSourceLock = [ordered]@{
            schemaVersion = 1
            gmp = [ordered]@{
                version = '6.3.0'
                url = 'https://example.invalid/gmp-6.3.0.tar.xz'
                archive = 'gmp-6.3.0.tar.xz'
                sha512 = ('a' * 128)
                extractedDirectory = 'gmp-6.3.0'
                identityFile = 'gmp-h.in'
            }
            mpfr = [ordered]@{
                version = '4.2.2'
                url = 'https://example.invalid/mpfr-4.2.2.tar.xz'
                archive = 'mpfr-4.2.2.tar.xz'
                sha512 = ('b' * 128)
                extractedDirectory = 'mpfr-4.2.2'
                identityFile = 'configure.ac'
            }
        }
        Set-Content -LiteralPath $sourceLockPath -Value ($validSourceLock | ConvertTo-Json -Depth 5)
        Read-SourceLock $sourceLockPath | Out-Null
        $invalidRequiredValues = @{
            version = 'not a version'
            url = 'http://example.invalid/source.tar.xz'
            archive = '..\source.tar.xz'
            sha512 = 'not-a-sha512'
            extractedDirectory = '..\source'
            identityFile = '..\configure.ac'
        }
        foreach ($sourceName in @('gmp', 'mpfr')) {
            foreach ($field in @('version', 'url', 'archive', 'sha512', 'extractedDirectory', 'identityFile')) {
                $missingLock = (($validSourceLock | ConvertTo-Json -Depth 5) | ConvertFrom-Json)
                $missingLock.$sourceName.PSObject.Properties.Remove($field)
                Set-Content -LiteralPath $sourceLockPath -Value ($missingLock | ConvertTo-Json -Depth 5)
                Invoke-ExpectedFailure { Read-SourceLock $sourceLockPath } "$sourceName-$field-missing"

                foreach ($blankValue in @($null, '', '   ')) {
                    $blankLock = (($validSourceLock | ConvertTo-Json -Depth 5) | ConvertFrom-Json)
                    $blankLock.$sourceName.$field = $blankValue
                    Set-Content -LiteralPath $sourceLockPath -Value ($blankLock | ConvertTo-Json -Depth 5)
                    Invoke-ExpectedFailure { Read-SourceLock $sourceLockPath } "$sourceName-$field-null-or-blank"
                }

                $invalidLock = (($validSourceLock | ConvertTo-Json -Depth 5) | ConvertFrom-Json)
                $invalidLock.$sourceName.$field = $invalidRequiredValues[$field]
                Set-Content -LiteralPath $sourceLockPath -Value ($invalidLock | ConvertTo-Json -Depth 5)
                Invoke-ExpectedFailure { Read-SourceLock $sourceLockPath } "$sourceName-$field-invalid"
            }
        }

        Invoke-ExpectedFailure { Get-ArtifactRecord 'missing.obj|fixture|object|8664' $work $started 'negative' } 'missing'
        $empty = Join-Path $work 'empty.obj'
        [IO.File]::WriteAllBytes($empty, (New-Object byte[] 0))
        Invoke-ExpectedFailure { Get-ArtifactRecord 'empty.obj|fixture|object|8664' $work $started 'negative' } 'empty'
        Invoke-ExpectedFailure { Get-ArtifactRecord 'x64.obj|fixture|object|AA64' $work $started 'negative' } 'wrong-machine'
        Invoke-ExpectedFailure { Get-ArtifactRecord 'x64.obj|fixture|mystery|8664' $work $started 'negative' } 'unknown-class'
        Invoke-ExpectedFailure { Get-ArtifactRecord 'x64.obj|fixture|object|8664|deadbeef' $work $started 'negative' } 'wrong-hash'
        (Get-Item $x64).LastWriteTimeUtc = $started.AddMinutes(-1)
        Invoke-ExpectedFailure { Get-ArtifactRecord 'x64.obj|fixture|object|8664' $work $started 'negative' } 'pre-run'
        (Get-Item $x64).LastWriteTimeUtc = [datetime]::UtcNow
        $outside = Join-Path (Split-Path -Parent $work) 'outside.obj'
        New-CoffObject $outside 0x8664
        Invoke-ExpectedFailure { Get-ArtifactRecord '..\outside.obj|fixture|object|8664' $work $started 'negative' } 'outside-staging'
        Remove-Item -LiteralPath $outside -Force
        Invoke-ExpectedFailure { Get-ArtifactRecord 'arm64.obj|mpfr|object|AA64' $work $started 'release_static_assembly_full64bit' } 'mpfr-full64bit'

        $sourceParent = Join-Path $work 'sources'
        $archiveRoot = Join-Path $work 'archive-root'
        $lockedSource = Join-Path $archiveRoot 'sample-1.0'
        $source = Join-Path $sourceParent 'sample-1.0'
        $overlay = Join-Path $work 'overlay'
        New-Item -ItemType Directory -Path $lockedSource, $source, $overlay | Out-Null
        Set-Content -LiteralPath (Join-Path $lockedSource 'configure.ac') -Value 'AC_INIT([sample], [1.0])'
        Set-Content -LiteralPath (Join-Path $lockedSource 'source.c') -Value 'int locked_source;'
        Copy-Item -LiteralPath (Join-Path $lockedSource 'configure.ac') -Destination $source
        Copy-Item -LiteralPath (Join-Path $lockedSource 'source.c') -Destination $source
        New-Item -ItemType Directory -Path (Join-Path $source 'win64') | Out-Null
        Set-Content -LiteralPath (Join-Path $overlay 'Makefile') -Value 'locked overlay'
        Copy-Item -LiteralPath (Join-Path $overlay 'Makefile') -Destination (Join-Path $source 'win64')
        $archive = Join-Path $sourceParent 'sample-1.0.tar'
        $tarPath = Resolve-TarApplicationPath
        Assert-Condition ([IO.Path]::IsPathRooted($tarPath) -and (Test-Path -LiteralPath $tarPath -PathType Leaf) -and (Split-Path -Leaf $tarPath) -ieq 'tar.exe') 'Real tar application resolution did not return an absolute existing tar.exe path.'
        $validTarCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'tar.exe'
            Source = $tarPath
            Path = $tarPath
            Definition = $tarPath
        }
        Assert-Condition ((Resolve-TarApplicationPath $validTarCommand) -ieq $tarPath) 'Constructed valid tar application metadata was not accepted.'
        foreach ($invalidType in @('Alias', 'Function', 'ExternalScript')) {
            $invalidCommand = [pscustomobject]@{
                CommandType = $invalidType
                Name = 'tar.exe'
                Source = $tarPath
                Path = $tarPath
                Definition = $tarPath
            }
            Invoke-ExpectedFailure { Resolve-TarApplicationPath $invalidCommand } "tar-command-type-$invalidType"
        }
        $relativeTarCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'tar.exe'
            Source = 'tar.exe'
            Path = 'tar.exe'
            Definition = 'tar.exe'
        }
        Invoke-ExpectedFailure { Resolve-TarApplicationPath $relativeTarCommand } 'tar-relative-path'
        $directoryTarPath = Join-Path $work 'directory\tar.exe'
        New-Item -ItemType Directory -Path $directoryTarPath | Out-Null
        $directoryTarCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'tar.exe'
            Source = $directoryTarPath
            Path = $directoryTarPath
            Definition = $directoryTarPath
        }
        Invoke-ExpectedFailure { Resolve-TarApplicationPath $directoryTarCommand } 'tar-non-leaf'
        $wrongNamePath = Join-Path $work 'not-tar.exe'
        [IO.File]::WriteAllBytes($wrongNamePath, (New-Object byte[] 1))
        $wrongNameCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'tar.exe'
            Source = $wrongNamePath
            Path = $wrongNamePath
            Definition = $wrongNamePath
        }
        Invoke-ExpectedFailure { Resolve-TarApplicationPath $wrongNameCommand } 'tar-filename-mismatch'
        $spoofedTarCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'tar.exe'
            Source = $tarPath
            Path = $wrongNamePath
            Definition = $tarPath
        }
        Invoke-ExpectedFailure { Resolve-TarApplicationPath $spoofedTarCommand } 'tar-metadata-spoof'
        & $tarPath -cf $archive -C $archiveRoot 'sample-1.0'
        Assert-Condition ($LASTEXITCODE -eq 0) 'Unable to create source-binding self-test archive.'
        $metadata = [pscustomobject]@{
            version = '1.0'
            url = 'https://example.invalid/sample-1.0.tar'
            archive = 'sample-1.0.tar'
            sha512 = Get-FileDigest $archive SHA512
            extractedDirectory = 'sample-1.0'
            identityFile = 'configure.ac'
        }
        $sourceRecord = Get-SourceRecord 'fixture' $metadata $source $overlay $work
        Assert-Condition ($sourceRecord.version -eq '1.0') 'Source identity positive test failed.'
        Assert-Condition ($sourceRecord.extractedFileCount -eq 2 -and $sourceRecord.appliedOverlayFileCount -eq 1) 'Source tree binding positive test failed.'
        $blankVersionMetadata = $metadata.PSObject.Copy()
        $blankVersionMetadata.version = ' '
        Invoke-ExpectedFailure { Get-SourceRecord 'fixture' $blankVersionMetadata $source $overlay $work } 'blank-version-empty-identity-regex'

        $externalTree = Join-Path $work 'external-tree'
        New-Item -ItemType Directory -Path $externalTree | Out-Null
        Set-Content -LiteralPath (Join-Path $externalTree 'external.c') -Value 'int unlocked_external_source;'
        foreach ($linkType in @('Junction', 'SymbolicLink')) {
            $candidateLink = Join-Path $source "external-$($linkType.ToLowerInvariant())"
            try {
                New-Item -ItemType $linkType -Path $candidateLink -Target $externalTree -ErrorAction Stop | Out-Null
            } catch {
                if ($linkType -eq 'SymbolicLink') { continue }
                throw
            }
            try {
                $failureMessage = ''
                try {
                    Assert-TreeMatches $lockedSource $source @('win64') | Out-Null
                } catch {
                    $failureMessage = $_.Exception.Message
                }
                Assert-Condition (-not [string]::IsNullOrWhiteSpace($failureMessage)) "Self-test 'candidate-directory-$($linkType.ToLowerInvariant())' did not fail closed."
                Assert-Condition ($failureMessage.Contains($candidateLink)) "Candidate directory $linkType failure did not identify the offending path."
            } finally {
                Remove-TestDirectoryReparsePoint $candidateLink $source
            }
            Assert-Condition (Test-Path -LiteralPath (Join-Path $externalTree 'external.c') -PathType Leaf) "Candidate directory $linkType cleanup removed the external target."

            $referenceLink = Join-Path $lockedSource "external-$($linkType.ToLowerInvariant())"
            New-Item -ItemType $linkType -Path $referenceLink -Target $externalTree -ErrorAction Stop | Out-Null
            try {
                $failureMessage = ''
                try {
                    Assert-TreeMatches $lockedSource $source @('win64') | Out-Null
                } catch {
                    $failureMessage = $_.Exception.Message
                }
                Assert-Condition (-not [string]::IsNullOrWhiteSpace($failureMessage)) "Self-test 'reference-directory-$($linkType.ToLowerInvariant())' did not fail closed."
                Assert-Condition ($failureMessage.Contains($referenceLink)) "Reference directory $linkType failure did not identify the offending path."
            } finally {
                Remove-TestDirectoryReparsePoint $referenceLink $lockedSource
            }
            Assert-Condition (Test-Path -LiteralPath (Join-Path $externalTree 'external.c') -PathType Leaf) "Reference directory $linkType cleanup removed the external target."
        }

        $overlayRepository = Join-Path $work 'overlay-repository'
        $gmpOverlayRoot = Join-Path $overlayRepository 'libgmp\win64'
        $mpfrOverlayRoot = Join-Path $overlayRepository 'libmpfr\win64'
        New-Item -ItemType Directory -Path $gmpOverlayRoot, $mpfrOverlayRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $gmpOverlayRoot 'Makefile') -Value 'gmp overlay'
        Set-Content -LiteralPath (Join-Path $mpfrOverlayRoot 'Makefile') -Value 'mpfr overlay'
        $gitPath = Resolve-GitApplicationPath
        Assert-Condition ([IO.Path]::IsPathRooted($gitPath) -and (Test-Path -LiteralPath $gitPath -PathType Leaf) -and (Split-Path -Leaf $gitPath) -ieq 'git.exe') 'Real Git application resolution did not return an absolute existing git.exe path.'
        $validGitCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'git.exe'
            Source = $gitPath
            Path = $gitPath
            Definition = $gitPath
        }
        Assert-Condition ((Resolve-GitApplicationPath $validGitCommand) -ieq $gitPath) 'Constructed valid Git application metadata was not accepted.'
        foreach ($invalidType in @('Alias', 'Function', 'ExternalScript', 'Script')) {
            $invalidCommand = [pscustomobject]@{
                CommandType = $invalidType
                Name = 'git.exe'
                Source = $gitPath
                Path = $gitPath
                Definition = $gitPath
            }
            Invoke-ExpectedFailure { Resolve-GitApplicationPath $invalidCommand } "git-command-type-$invalidType"
        }
        $relativeGitCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'git.exe'
            Source = 'git.exe'
            Path = 'git.exe'
            Definition = 'git.exe'
        }
        Invoke-ExpectedFailure { Resolve-GitApplicationPath $relativeGitCommand } 'git-relative-path'
        $directoryGitPath = Join-Path $work 'directory\git.exe'
        New-Item -ItemType Directory -Path $directoryGitPath | Out-Null
        $directoryGitCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'git.exe'
            Source = $directoryGitPath
            Path = $directoryGitPath
            Definition = $directoryGitPath
        }
        Invoke-ExpectedFailure { Resolve-GitApplicationPath $directoryGitCommand } 'git-non-leaf'
        $wrongGitNamePath = Join-Path $work 'not-git.exe'
        [IO.File]::WriteAllBytes($wrongGitNamePath, (New-Object byte[] 1))
        $wrongGitNameCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'git.exe'
            Source = $wrongGitNamePath
            Path = $wrongGitNamePath
            Definition = $wrongGitNamePath
        }
        Invoke-ExpectedFailure { Resolve-GitApplicationPath $wrongGitNameCommand } 'git-filename-mismatch'
        $wrongGitCommandName = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'not-git.exe'
            Source = $gitPath
            Path = $gitPath
            Definition = $gitPath
        }
        Invoke-ExpectedFailure { Resolve-GitApplicationPath $wrongGitCommandName } 'git-command-name-mismatch'
        $spoofedGitCommand = [pscustomobject]@{
            CommandType = 'Application'
            Name = 'git.exe'
            Source = $gitPath
            Path = $wrongGitNamePath
            Definition = $gitPath
        }
        Invoke-ExpectedFailure { Resolve-GitApplicationPath $spoofedGitCommand } 'git-metadata-spoof'
        & $gitPath -C $overlayRepository init --quiet
        Assert-Condition ($LASTEXITCODE -eq 0) 'Unable to initialize overlay-root self-test repository.'
        & $gitPath -C $overlayRepository add .
        Assert-Condition ($LASTEXITCODE -eq 0) 'Unable to stage overlay-root self-test files.'
        & $gitPath -C $overlayRepository -c user.name=write-manifest-self-test -c user.email=self-test@example.invalid commit --quiet -m 'overlay fixtures'
        Assert-Condition ($LASTEXITCODE -eq 0) 'Unable to commit overlay-root self-test files.'
        foreach ($missingOverlay in @(
            [ordered]@{ name = 'GMP'; path = $gmpOverlayRoot; relativePath = 'libgmp\win64' },
            [ordered]@{ name = 'MPFR'; path = $mpfrOverlayRoot; relativePath = 'libmpfr\win64' }
        )) {
            Remove-Item -LiteralPath $missingOverlay.path -Recurse -Force
            $failureMessage = ''
            try {
                Get-OverlayRecord $overlayRepository $true | Out-Null
            } catch {
                $failureMessage = $_.Exception.Message
            }
            Assert-Condition (-not [string]::IsNullOrWhiteSpace($failureMessage)) "Self-test 'missing-$($missingOverlay.name.ToLowerInvariant())-overlay' did not fail closed."
            Assert-Condition ($failureMessage.Contains($missingOverlay.path)) "Missing $($missingOverlay.name) overlay failure did not identify the missing path."
            Assert-Condition ($failureMessage.Contains("Restore the overlay at '$($missingOverlay.relativePath)'")) "Missing $($missingOverlay.name) overlay failure was not action-oriented."
            New-Item -ItemType Directory -Path $missingOverlay.path | Out-Null
            Set-Content -LiteralPath (Join-Path $missingOverlay.path 'Makefile') -Value "$($missingOverlay.name.ToLowerInvariant()) overlay"
        }

        $externalOverlayRoot = Join-Path $work 'external-overlay-root'
        New-Item -ItemType Directory -Path $externalOverlayRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $externalOverlayRoot 'external.mk') -Value 'must not be hashed'
        foreach ($linkType in @('Junction', 'SymbolicLink')) {
            $savedGmpOverlayRoot = Join-Path $overlayRepository "gmp-overlay-saved-$($linkType.ToLowerInvariant())"
            Move-Item -LiteralPath $gmpOverlayRoot -Destination $savedGmpOverlayRoot
            $rootLinkCreated = $false
            try {
                try {
                    New-Item -ItemType $linkType -Path $gmpOverlayRoot -Target $externalOverlayRoot -ErrorAction Stop | Out-Null
                    $rootLinkCreated = $true
                } catch {
                    if ($linkType -eq 'SymbolicLink') { continue }
                    throw
                }
                $failureMessage = ''
                try {
                    Get-OverlayRecord $overlayRepository $true | Out-Null
                } catch {
                    $failureMessage = $_.Exception.Message
                }
                Assert-Condition (-not [string]::IsNullOrWhiteSpace($failureMessage)) "Self-test 'overlay-root-$($linkType.ToLowerInvariant())' did not fail closed."
                Assert-Condition ($failureMessage.Contains($gmpOverlayRoot)) "Overlay root $linkType failure did not identify the offending path."
            } finally {
                if ($rootLinkCreated) {
                    Remove-TestDirectoryReparsePoint $gmpOverlayRoot (Split-Path -Parent $gmpOverlayRoot)
                }
                Move-Item -LiteralPath $savedGmpOverlayRoot -Destination $gmpOverlayRoot
            }
            Assert-Condition (Test-Path -LiteralPath (Join-Path $externalOverlayRoot 'external.mk') -PathType Leaf) "Overlay root $linkType cleanup removed the external target."

            $nestedLink = Join-Path $gmpOverlayRoot "external-$($linkType.ToLowerInvariant())"
            try {
                New-Item -ItemType $linkType -Path $nestedLink -Target $externalOverlayRoot -ErrorAction Stop | Out-Null
            } catch {
                if ($linkType -eq 'SymbolicLink') { continue }
                throw
            }
            try {
                $failureMessage = ''
                try {
                    Get-OverlayRecord $overlayRepository $true | Out-Null
                } catch {
                    $failureMessage = $_.Exception.Message
                }
                Assert-Condition (-not [string]::IsNullOrWhiteSpace($failureMessage)) "Self-test 'overlay-nested-directory-$($linkType.ToLowerInvariant())' did not fail closed."
                Assert-Condition ($failureMessage.Contains($nestedLink)) "Overlay nested directory $linkType failure did not identify the offending path."
            } finally {
                Remove-TestDirectoryReparsePoint $nestedLink $gmpOverlayRoot
            }
            Assert-Condition (Test-Path -LiteralPath (Join-Path $externalOverlayRoot 'external.mk') -PathType Leaf) "Overlay nested directory $linkType cleanup removed the external target."
        }

        $externalOverlayFile = Join-Path $work 'external-overlay-file.mk'
        Set-Content -LiteralPath $externalOverlayFile -Value 'must not be hashed'
        $nestedFileLink = Join-Path $gmpOverlayRoot 'external-file-symlink.mk'
        $fileLinkCreated = $false
        try {
            try {
                New-Item -ItemType SymbolicLink -Path $nestedFileLink -Target $externalOverlayFile -ErrorAction Stop | Out-Null
                $fileLinkCreated = $true
            } catch {
                $fileLinkCreated = $false
            }
            if ($fileLinkCreated) {
                $failureMessage = ''
                try {
                    Get-OverlayRecord $overlayRepository $true | Out-Null
                } catch {
                    $failureMessage = $_.Exception.Message
                }
                Assert-Condition (-not [string]::IsNullOrWhiteSpace($failureMessage)) "Self-test 'overlay-nested-file-symboliclink' did not fail closed."
                Assert-Condition ($failureMessage.Contains($nestedFileLink)) 'Overlay nested file symbolic link failure did not identify the offending path.'
            }
        } finally {
            if ($fileLinkCreated) {
                Remove-TestFileReparsePoint $nestedFileLink $gmpOverlayRoot
            }
        }
        Assert-Condition (Test-Path -LiteralPath $externalOverlayFile -PathType Leaf) 'Overlay nested file symbolic link cleanup removed the external target.'

        $maliciousMembers = @(
            '../archive-escape.txt',
            '..\archive-escape.txt',
            '/absolute/archive-escape.txt',
            '\absolute\archive-escape.txt',
            'C:/archive-escape.txt',
            'C:\archive-escape.txt',
            'C:archive-escape.txt',
            'sample-1.0//malformed.txt'
        )
        foreach ($maliciousMember in $maliciousMembers) {
            $maliciousArchive = Join-Path $sourceParent ('malicious-' + [guid]::NewGuid().ToString('N') + '.tar')
            New-TestTarArchive $maliciousArchive $maliciousMember 'must not be extracted'
            Invoke-ExpectedFailure { Assert-ArchiveMembersSafe $tarPath $maliciousArchive $work } "unsafe-archive-member-$maliciousMember"
        }
        $escapePath = Join-Path $work 'archive-escape.txt'
        $traversalArchive = Join-Path $sourceParent 'malicious-traversal.tar'
        New-TestTarArchive $traversalArchive '../archive-escape.txt' 'must not be extracted'
        $traversalMetadata = $metadata.PSObject.Copy()
        $traversalMetadata.archive = Split-Path -Leaf $traversalArchive
        $traversalMetadata.sha512 = Get-FileDigest $traversalArchive SHA512
        Invoke-ExpectedFailure { Get-SourceRecord 'fixture' $traversalMetadata $source $overlay $work } 'unsafe-archive-rejected-before-extraction'
        Assert-Condition (-not (Test-Path -LiteralPath $escapePath)) 'Unsafe archive member was extracted before validation.'

        Invoke-ExpectedFailure { Get-SourceRecord 'fixture' $metadata (Join-Path $sourceParent 'missing-1.0') $overlay $work } 'missing-source'
        $wrongDirectoryMetadata = $metadata.PSObject.Copy()
        $wrongDirectoryMetadata.extractedDirectory = 'sample-2.0'
        Invoke-ExpectedFailure { Get-SourceRecord 'fixture' $wrongDirectoryMetadata $source $overlay $work } 'wrong-extracted-version'
        $wrongHashMetadata = $metadata.PSObject.Copy()
        $wrongHashMetadata.sha512 = ('0' * 128)
        Invoke-ExpectedFailure { Get-SourceRecord 'fixture' $wrongHashMetadata $source $overlay $work } 'changed-archive-hash'
        Set-Content -LiteralPath (Join-Path $source 'source.c') -Value 'int tampered_source;'
        Invoke-ExpectedFailure { Get-SourceRecord 'fixture' $metadata $source $overlay $work } 'modified-extracted-source'
        Copy-Item -LiteralPath (Join-Path $lockedSource 'source.c') -Destination $source -Force
        Set-Content -LiteralPath (Join-Path $source 'win64\Makefile') -Value 'tampered overlay'
        Invoke-ExpectedFailure { Get-SourceRecord 'fixture' $metadata $source $overlay $work } 'modified-applied-overlay'
        Copy-Item -LiteralPath (Join-Path $overlay 'Makefile') -Destination (Join-Path $source 'win64') -Force

        $evidenceRoot = Join-Path $work 'evidence'
        New-Item -ItemType Directory -Path (Join-Path $evidenceRoot 'logs') | Out-Null
        $evidenceLog = Join-Path $evidenceRoot 'logs\check.log'
        $passingLog = @('Running test fixture ... PASS', '2 overall, 1 succeeded, 0 failed, 1 skipped.')
        Set-Content -LiteralPath $evidenceLog -Value $passingLog
        $evidenceLine = '{0}|entry|build-check|gmp|0|logs\check.log|"C:\Program Files\Microsoft Visual Studio\VC\Tools\MSVC\bin\Hostx64\x64\nmake.exe" /f win64\Makefile static_lib check' -f [datetime]::UtcNow.ToString('o')
        $evidenceFile = Join-Path $evidenceRoot 'commands.tsv'
        Set-Content -LiteralPath $evidenceFile -Value $evidenceLine
        $evidenceRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot
        $escape = [char]0x1b
        Set-Content -LiteralPath $evidenceLog -Value @(
            "${escape}[1;32mRunning test fixture ... PASS${escape}[0m",
            "${escape}[1;33m2${escape}[1;36m overall, ${escape}[1;32m1${escape}[1;36m succeeded, ${escape}[1;31m0${escape}[1;36m failed, ${escape}[1;33m1${escape}[1;36m skipped${escape}[0;0;0m."
        )
        Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot
        Set-Content -LiteralPath $evidenceLog -Value @(
            "${escape}[1;32mRunning test fixture ... PASS${escape}[0m",
            "${escape}[1;33m2${escape}[1;36m overall, ${escape}[1;32m1${escape}[1;36m succeeded, ${escape}[1;31m1${escape}[1;36m failed, ${escape}[1;33m0${escape}[1;36m skipped${escape}[0;0;0m."
        )
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'colored-failed-check-summary' 'Test-suite summary reports failed tests for gmp.'
        Set-Content -LiteralPath $evidenceLog -Value $passingLog
        Set-Content -LiteralPath $evidenceFile -Value ($evidenceLine -replace '"C:\\Program Files\\Microsoft Visual Studio\\VC\\Tools\\MSVC\\bin\\Hostx64\\x64\\nmake\.exe"', 'nmake')
        $bareEvidenceRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $bareEvidenceRecords 'gmp' 'entry' $evidenceRoot } 'bare-nmake-command'
        Set-Content -LiteralPath $evidenceFile -Value ($evidenceLine -replace '"C:\\Program Files\\Microsoft Visual Studio\\VC\\Tools\\MSVC\\bin\\Hostx64\\x64\\nmake\.exe"', 'nmake.exe')
        $bareExeEvidenceRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $bareExeEvidenceRecords 'gmp' 'entry' $evidenceRoot } 'bare-nmake-exe-command'
        $unquotedEvidenceLine = $evidenceLine -replace '"C:\\Program Files\\Microsoft Visual Studio\\VC\\Tools\\MSVC\\bin\\Hostx64\\x64\\nmake\.exe"', 'C:\BuildTools\VC\bin\nmake.exe'
        Set-Content -LiteralPath $evidenceFile -Value $unquotedEvidenceLine
        $unquotedEvidenceRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Assert-NativeTestEvidence $unquotedEvidenceRecords 'gmp' 'entry' $evidenceRoot
        $wrapperEvidenceLine = $evidenceLine -replace '"C:\\Program Files\\Microsoft Visual Studio\\VC\\Tools\\MSVC\\bin\\Hostx64\\x64\\nmake\.exe"', '"C:\Windows\System32\cmd.exe" /c nmake.exe'
        Set-Content -LiteralPath $evidenceFile -Value $wrapperEvidenceLine
        $wrapperEvidenceRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $wrapperEvidenceRecords 'gmp' 'entry' $evidenceRoot } 'wrapped-nmake-command'
        Set-Content -LiteralPath $evidenceFile -Value ($evidenceLine -replace '"C:\\Program Files\\Microsoft Visual Studio\\VC\\Tools\\MSVC\\bin\\Hostx64\\x64\\nmake\.exe"', 'C:\BuildTools\VC\bin\nmake.cmd')
        $nmakeCmdEvidenceRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $nmakeCmdEvidenceRecords 'gmp' 'entry' $evidenceRoot } 'nmake-wrapper-command'
        Set-Content -LiteralPath $evidenceFile -Value $evidenceLine
        $evidenceRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Set-Content -LiteralPath $evidenceLog -Value 'fabricated output without a test result'
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'fake-check-log'
        Set-Content -LiteralPath $evidenceLog -Value @('Running test fixture ... PASS', '2 overall, 1 succeeded, 1 failed, 0 skipped.')
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'failed-check-summary'
        Set-Content -LiteralPath $evidenceLog -Value 'Running test fixture ... PASS'
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'missing-check-summary'
        Set-Content -LiteralPath $evidenceLog -Value @('Running test fixture ... PASS', '1 overall, 1 succeeded, 0 failed, 0 skipped.', '2 overall, 2 succeeded, 0 failed, 0 skipped.')
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'multiple-check-summaries'
        Set-Content -LiteralPath $evidenceLog -Value @('Running test fixture ... PASS', '1 overall; 1 succeeded; 0 failed; 0 skipped')
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'malformed-check-summary'
        Set-Content -LiteralPath $evidenceLog -Value @('Running test fixture ... PASS', '3 overall, 1 succeeded, 0 failed, 1 skipped.')
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'inconsistent-check-summary'
        Set-Content -LiteralPath $evidenceLog -Value @('Running test fixture ... PASS', '1 overall, 0 succeeded, 0 failed, 1 skipped.')
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'zero-success-check-summary'
        Set-Content -LiteralPath $evidenceLog -Value @('Running test fixture ... PASS', '-1 overall, 1 succeeded, 0 failed, 0 skipped.')
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'gmp' 'entry' $evidenceRoot } 'negative-check-summary'
        Set-Content -LiteralPath $evidenceLog -Value $passingLog
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $evidenceRecords 'mpfr' 'entry' $evidenceRoot } 'mismatched-check-library'
        Set-Content -LiteralPath $evidenceFile -Value ($evidenceLine -replace '\|build-check\|', '|build-link|')
        $mismatchedRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $mismatchedRecords 'gmp' 'entry' $evidenceRoot } 'mismatched-check-action'
        Set-Content -LiteralPath $evidenceFile -Value ($evidenceLine -replace '\|0\|logs\\check\.log\|', '|1|logs\check.log|')
        $failedCommandRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $failedCommandRecords 'gmp' 'entry' $evidenceRoot } 'failed-check-command'
        Set-Content -LiteralPath $evidenceFile -Value ($evidenceLine -replace '"C:\\Program Files\\Microsoft Visual Studio\\VC\\Tools\\MSVC\\bin\\Hostx64\\x64\\nmake\.exe"', '"tools\nmake.exe"')
        $relativeCommandRecords = Get-CommandRecords $evidenceFile $evidenceRoot $started
        Invoke-ExpectedFailure { Assert-NativeTestEvidence $relativeCommandRecords 'gmp' 'entry' $evidenceRoot } 'relative-nmake-command'
        Remove-Item -LiteralPath $evidenceLog
        Invoke-ExpectedFailure { Get-CommandRecords $evidenceFile $evidenceRoot $started } 'missing-check-log'

        $legacy = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'x86-64') -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $legacy) {
            Invoke-ExpectedFailure { Get-ArtifactRecord $legacy.FullName $work $started 'legacy' } 'legacy-prebuilt'
        }

        $duplicates = @('x64.obj|fixture|object|8664', 'x64.obj|fixture|object|8664')
        $seen = @{}
        Invoke-ExpectedFailure {
            foreach ($spec in $duplicates) {
                $key = ($spec -split '\|', 2)[0].ToLowerInvariant()
                Assert-Condition (-not $seen.ContainsKey($key)) "Duplicate artifact: $key"
                $seen[$key] = $true
            }
        } 'duplicate'

        Write-Host 'write-manifest self-test passed: x64=8664 arm64=AA64; all negative cases rejected.'
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
        $parent = Split-Path -Parent $work
        if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $parent -Force
        }
    }
}

try {
    if ($SelfTest) {
        Invoke-SelfTest
        exit 0
    }

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($StagingRoot)) 'StagingRoot is required.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($RunId)) 'RunId is required.'
    $root = Get-FullPath $StagingRoot

    if ($Aggregate) {
        Assert-Condition (Test-Path -LiteralPath $root -PathType Container) "Staging root does not exist: $root"
        $entryFiles = @(Get-ChildItem -LiteralPath $root -Filter 'manifest.json' -File -Recurse | Where-Object { $_.DirectoryName -ne $root })
        Assert-Condition ($entryFiles.Count -gt 0) 'No entry manifests were found for aggregation.'
        $entries = @()
        foreach ($file in $entryFiles | Sort-Object FullName) {
            $item = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            Assert-Condition ($item.schemaVersion -eq 1 -and $item.runId -ceq $RunId) "Invalid or foreign entry manifest: $($file.FullName)"
            $entries += $item
        }
        $aggregateManifest = [ordered]@{
            schemaVersion = 1
            runId = $RunId
            completedUtc = [datetime]::UtcNow.ToString('o')
            stagingRoot = $root
            entries = $entries
        }
        $aggregatePath = Join-Path $root 'manifest.json'
        $aggregateManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $aggregatePath -Encoding UTF8
        Write-Host "Aggregate manifest: $aggregatePath"
        exit 0
    }

    Assert-Condition ($RunStartUtc -ne [datetime]::MinValue) 'RunStartUtc is required.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Architecture)) 'Architecture is required.'
    $lock = Read-SourceLock $SourcesFile
    $repositoryRoot = Get-FullPath (Join-Path $PSScriptRoot '..')
    $sourceReceiptPath = Join-Path $root 'source-validation.json'

    if ($ValidateSourcesOnly) {
        if (Test-Path -LiteralPath $root) {
            Assert-Condition (Test-Path -LiteralPath $root -PathType Container) 'Output path exists and is not a directory.'
            $unexpected = @(Get-ChildItem -LiteralPath $root -Force | Where-Object { $_.Name -notin @('logs', 'commands.tsv') })
            Assert-Condition ($unexpected.Count -eq 0) 'Output/staging directory contained data before the current run.'
        }
        $gmpRecord = Get-SourceRecord 'gmp' $lock.gmp $GmpSource (Join-Path $repositoryRoot 'libgmp\win64') $root
        $mpfrRecord = Get-SourceRecord 'mpfr' $lock.mpfr $MpfrSource (Join-Path $repositoryRoot 'libmpfr\win64') $root
        $overlay = Get-OverlayRecord $repositoryRoot ([bool]$AllowDirtyOverlay)
        $sourceReceipt = [ordered]@{
            schemaVersion = 1
            runId = $RunId
            runStartUtc = $RunStartUtc.ToUniversalTime().ToString('o')
            validatedUtc = [datetime]::UtcNow.ToString('o')
            gmpSource = Get-FullPath $GmpSource
            mpfrSource = Get-FullPath $MpfrSource
            sources = @($gmpRecord, $mpfrRecord)
            overlay = $overlay
        }
        $sourceReceipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $sourceReceiptPath -Encoding UTF8
        Write-Host "Validated locked GMP $($lock.gmp.version), MPFR $($lock.mpfr.version), overlay $($overlay.commit)."
        exit 0
    }

    Assert-Condition (Test-Path -LiteralPath $root -PathType Container) "Staging root does not exist: $root"
    Assert-Condition (Test-Path -LiteralPath $sourceReceiptPath -PathType Leaf) 'Source-validation receipt is missing; run locked-source preflight first.'
    $sourceReceiptItem = Get-Item -LiteralPath $sourceReceiptPath
    Assert-Condition ($sourceReceiptItem.LastWriteTimeUtc -ge $RunStartUtc.ToUniversalTime()) 'Source-validation receipt predates the run.'
    $sourceReceipt = Get-Content -LiteralPath $sourceReceiptPath -Raw | ConvertFrom-Json
    Assert-Condition ($sourceReceipt.schemaVersion -eq 1 -and $sourceReceipt.runId -ceq $RunId) 'Source-validation receipt does not belong to this run.'
    Assert-Condition ((Get-FullPath ([string]$sourceReceipt.gmpSource)) -ceq (Get-FullPath $GmpSource)) 'GMP source path differs from validated preflight.'
    Assert-Condition ((Get-FullPath ([string]$sourceReceipt.mpfrSource)) -ceq (Get-FullPath $MpfrSource)) 'MPFR source path differs from validated preflight.'
    $gmpRecord = $sourceReceipt.sources | Where-Object { $_.name -eq 'gmp' } | Select-Object -First 1
    $mpfrRecord = $sourceReceipt.sources | Where-Object { $_.name -eq 'mpfr' } | Select-Object -First 1
    Assert-Condition ($null -ne $gmpRecord -and $null -ne $mpfrRecord) 'Source-validation receipt is incomplete.'
    Assert-Condition ((Get-FileDigest (Join-Path (Split-Path -Parent $GmpSource) ([string]$lock.gmp.archive)) SHA512) -ceq [string]$gmpRecord.archiveSha512) 'GMP archive changed after preflight.'
    Assert-Condition ((Get-FileDigest (Join-Path (Split-Path -Parent $MpfrSource) ([string]$lock.mpfr.archive)) SHA512) -ceq [string]$mpfrRecord.archiveSha512) 'MPFR archive changed after preflight.'
    $overlay = $sourceReceipt.overlay
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Entry)) 'Entry is required.'
    $artifactSpecs = @($ArtifactSpec -split ';;' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Condition ($artifactSpecs.Count -gt 0) 'At least one artifact is required.'
    $seenArtifacts = @{}
    $artifacts = @()
    foreach ($spec in $artifactSpecs) {
        $relative = ($spec -split '\|', 2)[0]
        $key = $relative.ToLowerInvariant()
        Assert-Condition (-not $seenArtifacts.ContainsKey($key)) "Duplicate artifact path: $relative"
        $seenArtifacts[$key] = $true
        $artifacts += Get-ArtifactRecord $spec $root $RunStartUtc $Entry
    }
    $commands = Get-CommandRecords $CommandLog $root $RunStartUtc
    Assert-Condition (-not ($commands | Where-Object { $_.exitCode -ne 0 })) 'A successful manifest cannot include a failed command.'

    $nativeArchitecture = Get-NativeOSArchitecture
    if ($null -eq $nativeArchitecture) { $nativeArchitecture = 'unknown' }
    $native = Test-IsNative $Architecture $nativeArchitecture
    $assemblerRequired = $Entry -match 'assembly' -and $Entry -notmatch 'noassembly'
    $libraries = @()
    foreach ($name in @('gmp', 'mpfr')) {
        if ($artifacts.library -contains $name) {
            if ($native) {
                Assert-NativeTestEvidence $commands $name $Entry $root
            }
            $libraries += [ordered]@{
                name = $name
                status = $(if ($native) { 'native_tests_passed' } else { 'not_run_cross' })
            }
        }
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        runId = $RunId
        runStartUtc = $RunStartUtc.ToUniversalTime().ToString('o')
        entryCompletedUtc = [datetime]::UtcNow.ToString('o')
        stagingRoot = $root
        architecture = $Architecture
        nativeExecution = $native
        entry = $Entry
        makeVariables = @($MakeVariables -split ';;' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        sources = @($gmpRecord, $mpfrRecord)
        overlay = $overlay
        environment = [ordered]@{
            os = [Environment]::OSVersion.VersionString
            processArchitecture = [string]$env:PROCESSOR_ARCHITECTURE
            nativeArchitecture = $nativeArchitecture
            tools = @(
                (Get-ToolRecord 'cl.exe' $true),
                (Get-ToolRecord 'link.exe' $true),
                (Get-ToolRecord 'lib.exe' $true),
                (Get-ToolRecord 'nmake.exe' $true),
                (Get-ToolRecord $(if ($Architecture -eq 'arm64') { 'armasm64.exe' } else { 'ml64.exe' }) $assemblerRequired)
            )
        }
        commands = $commands
        libraries = $libraries
        artifacts = $artifacts
        limitations = @(
            'Existing checked-in prebuilt binaries are unverified and are not certified by this manifest.',
            'FULL_64BIT= is GMP-only and is incompatible with MPFR.',
            (Get-ExecutionLimitation $Architecture $nativeArchitecture $native)
        )
    }

    if ($ValidateOnly) {
        Write-Host "Manifest validation passed for entry '$Entry' ($($artifacts.Count) artifacts)."
        exit 0
    }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path (Join-Path $root $Entry) 'manifest.json'
    }
    $manifestPath = Get-FullPath $OutputPath
    Assert-Condition (Test-PathInside $manifestPath $root) 'Manifest output must be inside staging root.'
    $manifestDirectory = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $manifestDirectory)) { New-Item -ItemType Directory -Path $manifestDirectory | Out-Null }
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Host "Entry manifest: $manifestPath"
    exit 0
} catch {
    [Console]::Error.WriteLine((Format-ErrorRecordDiagnostic $_))
    exit 1
}
