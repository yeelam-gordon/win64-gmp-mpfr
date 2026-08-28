@ECHO OFF
SETLOCAL EnableExtensions EnableDelayedExpansion
REM The NMake recipes invoke freshly built helper executables by basename.
SET "NoDefaultCurrentDirectoryInExePath="

SET "SCRIPT_ROOT=%~dp0"
SET "REPO_ROOT=%SCRIPT_ROOT%.."
SET "SOURCES_FILE=%SCRIPT_ROOT%sources.json"
SET "MANIFEST_WRITER=%SCRIPT_ROOT%write-manifest.ps1"
SET "GMP_SOURCE=%SCRIPT_ROOT%..\..\gmp-6.3.0"
SET "MPFR_SOURCE=%SCRIPT_ROOT%..\..\mpfr-4.2.2"
SET "TARGET_ARCH=arm64"
SET "EXPECTED_MACHINE=AA64"
SET "SELECTED_ENTRY="
SET "OUTPUT_ROOT="
SET "ALLOW_DIRTY="
SET "SELF_TEST="
SET "BUILT_COUNT=0"
SET "COMMAND_INDEX=0"
SET "RUN_RC=0"
SET "GMP_ALIAS_CREATED="
SET "GMP_ALIAS_DRIVE="
SET "MPFR_GMP_SOURCE=%GMP_SOURCE%"

FOR /F %%I IN ('powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')"') DO SET "RUN_ID=arm64-%%I"
FOR /F %%I IN ('powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('o')"') DO SET "RUN_START=%%I"

:PARSE_ARGS
IF "%~1"=="" GOTO ARGS_DONE
IF /I "%~1"=="--gmp-source" (
  IF "%~2"=="" GOTO USAGE
  SET "GMP_SOURCE=%~f2"
  SHIFT & SHIFT & GOTO PARSE_ARGS
)
IF /I "%~1"=="--mpfr-source" (
  IF "%~2"=="" GOTO USAGE
  SET "MPFR_SOURCE=%~f2"
  SHIFT & SHIFT & GOTO PARSE_ARGS
)
IF /I "%~1"=="--output" (
  IF "%~2"=="" GOTO USAGE
  SET "OUTPUT_ROOT=%~f2"
  SHIFT & SHIFT & GOTO PARSE_ARGS
)
IF /I "%~1"=="--entry" (
  IF "%~2"=="" GOTO USAGE
  SET "SELECTED_ENTRY=%~2"
  SHIFT & SHIFT & GOTO PARSE_ARGS
)
IF /I "%~1"=="--allow-dirty-overlay" (
  SET "ALLOW_DIRTY=-AllowDirtyOverlay"
  SHIFT & GOTO PARSE_ARGS
)
IF /I "%~1"=="--self-test-fail-fast" (
  SET "SELF_TEST=1"
  SHIFT & GOTO PARSE_ARGS
)
GOTO USAGE

:ARGS_DONE
IF NOT DEFINED OUTPUT_ROOT SET "OUTPUT_ROOT=%SCRIPT_ROOT%..\..\win64-gmp-mpfr-runs\%RUN_ID%"

IF DEFINED SELF_TEST GOTO SELF_TEST

IF /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
  SET "TEST_TARGET=check"
) ELSE IF /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" (
  SET "TEST_TARGET=check"
) ELSE (
  SET "TEST_TARGET="
)

IF EXIST "%OUTPUT_ROOT%" (
  FOR /F "delims=" %%I IN ('dir /b /a "%OUTPUT_ROOT%" 2^>NUL') DO (
    ECHO ERROR: output/staging directory must initially be empty: "%OUTPUT_ROOT%"
    EXIT /B 65
  )
) ELSE (
  MKDIR "%OUTPUT_ROOT%"
  IF ERRORLEVEL 1 EXIT /B !ERRORLEVEL!
)
MKDIR "%OUTPUT_ROOT%\logs"
IF ERRORLEVEL 1 EXIT /B !ERRORLEVEL!
SET "COMMAND_LOG=%OUTPUT_ROOT%\commands.tsv"
SET "LOG_ROOT=%OUTPUT_ROOT%\logs"

SET "CURRENT_ENTRY=preflight"
CALL :RUN powershell -NoProfile -ExecutionPolicy Bypass -File "%MANIFEST_WRITER%" -ValidateSourcesOnly -SourcesFile "%SOURCES_FILE%" -StagingRoot "%OUTPUT_ROOT%" -GmpSource "%GMP_SOURCE%" -MpfrSource "%MPFR_SOURCE%" -RunStartUtc "%RUN_START%" -RunId "%RUN_ID%" -Architecture "%TARGET_ARCH%" %ALLOW_DIRTY%
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :RUN powershell -NoProfile -Command "$p=New-Object Diagnostics.Process; $p.StartInfo.FileName='cl.exe'; $p.StartInfo.UseShellExecute=$false; $p.StartInfo.RedirectStandardError=$true; $p.StartInfo.RedirectStandardOutput=$true; [void]$p.Start(); $o=$p.StandardError.ReadToEnd()+$p.StandardOutput.ReadToEnd(); $p.WaitForExit(); Write-Host $o; if($o -notmatch 'for ARM64'){exit 86}"
IF NOT "!RUN_RC!"=="0" GOTO FAILED

CALL :RUN CD /D "%GMP_SOURCE%"
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :RUN nmake /f win64\Makefile patch
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :RUN CD /D "%MPFR_SOURCE%"
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :RUN nmake /f win64\Makefile patch
IF NOT "!RUN_RC!"=="0" GOTO FAILED

CALL :MAYBE_STATIC debug_static_noassembly "ARM64= DEBUG=" "ARM64= DEBUG=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_STATIC debug_static_assembly "ARM64= DEBUG= ASSEMBLY=" "ARM64= DEBUG=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_DYNAMIC debug_dynamic_noassembly "ARM64= DEBUG= DYNAMIC_RT= LINK_DLL=" "ARM64= DEBUG= DYNAMIC_RT= LINK_DLL=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_DYNAMIC debug_dynamic_assembly "ARM64= DEBUG= DYNAMIC_RT= LINK_DLL= ASSEMBLY=" "ARM64= DEBUG= DYNAMIC_RT= LINK_DLL=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_STATIC release_static_noassembly "ARM64=" "ARM64=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_STATIC release_static_assembly "ARM64= ASSEMBLY=" "ARM64=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_DYNAMIC release_dynamic_noassembly "ARM64= DYNAMIC_RT= LINK_DLL=" "ARM64= DYNAMIC_RT= LINK_DLL=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_DYNAMIC release_dynamic_assembly "ARM64= DYNAMIC_RT= LINK_DLL= ASSEMBLY=" "ARM64= DYNAMIC_RT= LINK_DLL=" yes
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_STATIC release_static_assembly_full64bit "FULL_64BIT= ARM64= ASSEMBLY=" "" no
IF NOT "!RUN_RC!"=="0" GOTO FAILED
CALL :MAYBE_DYNAMIC release_dynamic_assembly_full64bit "FULL_64BIT= ARM64= DYNAMIC_RT= LINK_DLL= ASSEMBLY=" "" no
IF NOT "!RUN_RC!"=="0" GOTO FAILED

IF "!BUILT_COUNT!"=="0" (
  ECHO ERROR: unknown --entry value "%SELECTED_ENTRY%".
  EXIT /B 64
)
SET "CURRENT_ENTRY=aggregate"
CALL :RUN powershell -NoProfile -ExecutionPolicy Bypass -File "%MANIFEST_WRITER%" -Aggregate -SourcesFile "%SOURCES_FILE%" -StagingRoot "%OUTPUT_ROOT%" -RunId "%RUN_ID%"
IF NOT "!RUN_RC!"=="0" GOTO FAILED
ECHO SUCCESS: !BUILT_COUNT! Arm64 matrix entry or entries staged at "%OUTPUT_ROOT%".
EXIT /B 0

:MAYBE_STATIC
IF DEFINED SELECTED_ENTRY IF /I NOT "%SELECTED_ENTRY%"=="%~1" EXIT /B 0
CALL :BUILD_STATIC "%~1" "%~2" "%~3" "%~4"
EXIT /B !RUN_RC!

:MAYBE_DYNAMIC
IF DEFINED SELECTED_ENTRY IF /I NOT "%SELECTED_ENTRY%"=="%~1" EXIT /B 0
CALL :BUILD_DYNAMIC "%~1" "%~2" "%~3" "%~4"
EXIT /B !RUN_RC!

:BUILD_STATIC
SET "CURRENT_ENTRY=%~1"
SET "GMP_FLAGS=%~2"
SET "MPFR_FLAGS=%~3"
SET "WITH_MPFR=%~4"
ECHO BUILDING: !CURRENT_ENTRY!
CALL :RUN CD /D "%GMP_SOURCE%"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
CALL :RUN nmake /f win64\Makefile clean
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
SET "RUN_ACTION=build-link"
IF DEFINED TEST_TARGET SET "RUN_ACTION=build-check"
SET "RUN_LIBRARY=gmp"
CALL :RUN nmake /f win64\Makefile !GMP_FLAGS! static_lib !TEST_TARGET!
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
CALL :RUN MKDIR "%OUTPUT_ROOT%\!CURRENT_ENTRY!"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
CALL :RUN COPY /Y "%GMP_SOURCE%\libgmp.lib" "%OUTPUT_ROOT%\!CURRENT_ENTRY!\libgmp.lib"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
IF /I "!WITH_MPFR!"=="yes" (
  CALL :RUN CD /D "%MPFR_SOURCE%"
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :RUN nmake /f win64\Makefile clean
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :ENSURE_GMP_ALIAS
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  SET "RUN_ACTION=build-link"
  IF DEFINED TEST_TARGET SET "RUN_ACTION=build-check"
  SET "RUN_LIBRARY=mpfr"
  IF DEFINED GMP_ALIAS_CREATED (
    CALL :RUN nmake /f win64\Makefile !MPFR_FLAGS! LIBGMP_BUILDDIR=!MPFR_GMP_SOURCE! static_lib !TEST_TARGET!
  ) ELSE (
    CALL :RUN nmake /f win64\Makefile !MPFR_FLAGS! LIBGMP_BUILDDIR="%GMP_SOURCE%" static_lib !TEST_TARGET!
  )
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :REMOVE_GMP_ALIAS
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :RUN COPY /Y "%MPFR_SOURCE%\libmpfr.lib" "%OUTPUT_ROOT%\!CURRENT_ENTRY!\libmpfr.lib"
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :WRITE_MANIFEST "!CURRENT_ENTRY!\libgmp.lib|gmp|static|%EXPECTED_MACHINE%" "!CURRENT_ENTRY!\libmpfr.lib|mpfr|static|%EXPECTED_MACHINE%"
) ELSE (
  CALL :WRITE_MANIFEST "!CURRENT_ENTRY!\libgmp.lib|gmp|static|%EXPECTED_MACHINE%"
)
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
SET /A BUILT_COUNT+=1
EXIT /B 0

:BUILD_DYNAMIC
SET "CURRENT_ENTRY=%~1"
SET "GMP_FLAGS=%~2"
SET "MPFR_FLAGS=%~3"
SET "WITH_MPFR=%~4"
ECHO BUILDING: !CURRENT_ENTRY!
CALL :RUN CD /D "%GMP_SOURCE%"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
CALL :RUN nmake /f win64\Makefile clean
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
SET "RUN_ACTION=build-link"
IF DEFINED TEST_TARGET SET "RUN_ACTION=build-check"
SET "RUN_LIBRARY=gmp"
CALL :RUN nmake /f win64\Makefile !GMP_FLAGS! dynamic_lib !TEST_TARGET!
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
CALL :RUN MKDIR "%OUTPUT_ROOT%\!CURRENT_ENTRY!"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
CALL :RUN COPY /Y "%GMP_SOURCE%\libgmp.dll" "%OUTPUT_ROOT%\!CURRENT_ENTRY!\libgmp.dll"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
CALL :RUN COPY /Y "%GMP_SOURCE%\libgmp-imp.lib" "%OUTPUT_ROOT%\!CURRENT_ENTRY!\libgmp-imp.lib"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
IF /I "!WITH_MPFR!"=="yes" (
  CALL :RUN CD /D "%MPFR_SOURCE%"
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :RUN nmake /f win64\Makefile clean
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :ENSURE_GMP_ALIAS
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  SET "RUN_ACTION=build-link"
  IF DEFINED TEST_TARGET SET "RUN_ACTION=build-check"
  SET "RUN_LIBRARY=mpfr"
  IF DEFINED GMP_ALIAS_CREATED (
    CALL :RUN nmake /f win64\Makefile !MPFR_FLAGS! LIBGMP_BUILDDIR=!MPFR_GMP_SOURCE! dynamic_lib !TEST_TARGET!
  ) ELSE (
    CALL :RUN nmake /f win64\Makefile !MPFR_FLAGS! LIBGMP_BUILDDIR="%GMP_SOURCE%" dynamic_lib !TEST_TARGET!
  )
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :REMOVE_GMP_ALIAS
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :RUN COPY /Y "%MPFR_SOURCE%\libmpfr.dll" "%OUTPUT_ROOT%\!CURRENT_ENTRY!\libmpfr.dll"
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :RUN COPY /Y "%MPFR_SOURCE%\libmpfr-imp.lib" "%OUTPUT_ROOT%\!CURRENT_ENTRY!\libmpfr-imp.lib"
  IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
  CALL :WRITE_MANIFEST "!CURRENT_ENTRY!\libgmp.dll|gmp|dll|%EXPECTED_MACHINE%" "!CURRENT_ENTRY!\libgmp-imp.lib|gmp|import|%EXPECTED_MACHINE%" "!CURRENT_ENTRY!\libmpfr.dll|mpfr|dll|%EXPECTED_MACHINE%" "!CURRENT_ENTRY!\libmpfr-imp.lib|mpfr|import|%EXPECTED_MACHINE%"
) ELSE (
  CALL :WRITE_MANIFEST "!CURRENT_ENTRY!\libgmp.dll|gmp|dll|%EXPECTED_MACHINE%" "!CURRENT_ENTRY!\libgmp-imp.lib|gmp|import|%EXPECTED_MACHINE%"
)
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
SET /A BUILT_COUNT+=1
EXIT /B 0

:WRITE_MANIFEST
SET "ARTIFACT_SPECS=%~1"
IF NOT "%~2"=="" SET "ARTIFACT_SPECS=!ARTIFACT_SPECS!;;%~2"
IF NOT "%~3"=="" SET "ARTIFACT_SPECS=!ARTIFACT_SPECS!;;%~3"
IF NOT "%~4"=="" SET "ARTIFACT_SPECS=!ARTIFACT_SPECS!;;%~4"
CALL :RUN powershell -NoProfile -ExecutionPolicy Bypass -File "%MANIFEST_WRITER%" -SourcesFile "%SOURCES_FILE%" -StagingRoot "%OUTPUT_ROOT%" -GmpSource "%GMP_SOURCE%" -MpfrSource "%MPFR_SOURCE%" -RunStartUtc "%RUN_START%" -RunId "%RUN_ID%" -Architecture "%TARGET_ARCH%" -Entry "!CURRENT_ENTRY!" -MakeVariables "!GMP_FLAGS!;;!MPFR_FLAGS!" -CommandLog "%COMMAND_LOG%" -ArtifactSpec "!ARTIFACT_SPECS!" %ALLOW_DIRTY%
EXIT /B !RUN_RC!

:ENSURE_GMP_ALIAS
SET "MPFR_GMP_SOURCE=%GMP_SOURCE%"
IF "%GMP_SOURCE: =%"=="%GMP_SOURCE%" (
  SET "RUN_RC=0"
  EXIT /B 0
)
IF DEFINED GMP_ALIAS_CREATED (
  SET "MPFR_GMP_SOURCE=!GMP_ALIAS_DRIVE!\"
  SET "RUN_RC=0"
  EXIT /B 0
)
SET "GMP_ALIAS_DRIVE="
FOR %%D IN (Z Y X W V U T S R Q P) DO IF NOT DEFINED GMP_ALIAS_DRIVE IF NOT EXIST %%D:\NUL SET "GMP_ALIAS_DRIVE=%%D:"
IF NOT DEFINED GMP_ALIAS_DRIVE (
  ECHO ERROR: no unused drive letter is available for the run-scoped GMP alias.
  SET "RUN_RC=66"
  EXIT /B 66
)
SET "RUN_ACTION=alias-create"
SET "RUN_LIBRARY=gmp"
CALL :RUN subst !GMP_ALIAS_DRIVE! "%GMP_SOURCE%"
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
SET "GMP_ALIAS_CREATED=1"
SET "MPFR_GMP_SOURCE=!GMP_ALIAS_DRIVE!\"
ECHO GMP alias for this run: !MPFR_GMP_SOURCE!
EXIT /B 0

:REMOVE_GMP_ALIAS
IF NOT DEFINED GMP_ALIAS_CREATED (
  SET "RUN_RC=0"
  EXIT /B 0
)
SET "RUN_ACTION=alias-remove"
SET "RUN_LIBRARY=gmp"
CALL :RUN subst !GMP_ALIAS_DRIVE! /D
IF NOT "!RUN_RC!"=="0" EXIT /B !RUN_RC!
SET "GMP_ALIAS_CREATED="
SET "MPFR_GMP_SOURCE=%GMP_SOURCE%"
EXIT /B 0

:RUN
IF NOT DEFINED RUN_ACTION SET "RUN_ACTION=command"
IF NOT DEFINED RUN_LIBRARY SET "RUN_LIBRARY=-"
SET /A COMMAND_INDEX+=1
SET "LOG_NAME=00000!COMMAND_INDEX!"
SET "LOG_NAME=command-!LOG_NAME:~-5!.log"
SET "LOG_REL=logs\!LOG_NAME!"
ECHO [!CURRENT_ENTRY!] ^> %*
CALL %* >"!LOG_ROOT!\!LOG_NAME!" 2>&1
SET "RUN_RC=!ERRORLEVEL!"
TYPE "!LOG_ROOT!\!LOG_NAME!"
FOR /F %%I IN ('powershell -NoProfile -Command "[DateTime]::UtcNow.ToString('o')"') DO SET "STAMP=%%I"
>>"!COMMAND_LOG!" ECHO(!STAMP!^|!CURRENT_ENTRY!^|!RUN_ACTION!^|!RUN_LIBRARY!^|!RUN_RC!^|!LOG_REL!^|%*
IF NOT "!RUN_RC!"=="0" ECHO ERROR: [!CURRENT_ENTRY!] command failed with exit code !RUN_RC!.
SET "RUN_ACTION="
SET "RUN_LIBRARY="
EXIT /B !RUN_RC!

:SELF_TEST
SET "OUTPUT_ROOT=%SCRIPT_ROOT%.test-work\fail-fast-%RUN_ID%"
IF EXIST "%OUTPUT_ROOT%" RMDIR /S /Q "%OUTPUT_ROOT%"
MKDIR "%OUTPUT_ROOT%\logs" || EXIT /B !ERRORLEVEL!
SET "COMMAND_LOG=%OUTPUT_ROOT%\commands.tsv"
SET "LOG_ROOT=%OUTPUT_ROOT%\logs"
SET "CURRENT_ENTRY=self-test-fail-fast"
CALL :RUN cmd /d /c exit 37
SET "SAVED_RC=!RUN_RC!"
IF "!SAVED_RC!"=="0" SET "SAVED_RC=99"
RMDIR /S /Q "%OUTPUT_ROOT%"
EXIT /B !SAVED_RC!

:FAILED
SET "SAVED_RC=!RUN_RC!"
IF "!SAVED_RC!"=="0" SET "SAVED_RC=1"
IF DEFINED GMP_ALIAS_CREATED (
  CALL :REMOVE_GMP_ALIAS
  IF NOT "!RUN_RC!"=="0" ECHO ERROR: GMP alias cleanup also failed with exit code !RUN_RC!.
)
ECHO ERROR: build stopped immediately; exit code !SAVED_RC!.
EXIT /B !SAVED_RC!

:USAGE
ECHO Usage: %~nx0 [--gmp-source DIR] [--mpfr-source DIR] [--output EMPTY_DIR] [--entry NAME] [--allow-dirty-overlay]
ECHO        %~nx0 --self-test-fail-fast
EXIT /B 64
