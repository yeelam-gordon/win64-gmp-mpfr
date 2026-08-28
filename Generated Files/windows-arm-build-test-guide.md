# Windows Arm GMP/MPFR build and test guide

## Evidence levels

Keep these claims separate:

1. **x64 native:** build plus `check` executed on AMD64/x64.
2. **Arm64 cross:** compilation/link and `AA64` inspection on AMD64; runtime is
   `not_run_cross`.
3. **Arm64 native:** build, tests, and consumers executed by an Arm64 process on
   Windows Arm64.

Cross compilation is never native runtime evidence.

## Prerequisites

- Windows with Visual Studio 2026 C++ tools.
- x64 and Arm64 MSVC components.
- Git for Windows `patch.exe`.
- PowerShell, `curl.exe`, and `tar.exe`.
- A clean clone of this repository.
- For native certification, a physical or hosted native Windows Arm64 runner.

Confirm the host and tool target:

```powershell
$env:PROCESSOR_ARCHITECTURE
& $env:ComSpec /c 'call "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" amd64_arm64 >nul && cl 2>&1'
```

The first command must report `ARM64` before any result is called native
Arm64. `cl` must say `for ARM64` for Arm64 builds.

## Obtain locked sources

From a disposable directory beside, not inside, the product checkout:

```powershell
curl.exe -L --fail https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz -o gmp-6.3.0.tar.xz
curl.exe -L --fail https://www.mpfr.org/mpfr-4.2.2/mpfr-4.2.2.tar.xz -o mpfr-4.2.2.tar.xz
Get-FileHash .\gmp-6.3.0.tar.xz -Algorithm SHA512
Get-FileHash .\mpfr-4.2.2.tar.xz -Algorithm SHA512
```

The hashes must exactly match `prebuilt\sources.json`. If a canonical host is
temporarily unreachable, use a trusted mirror only if the resulting archive
has the exact locked SHA-512.

Extract and apply the repository overlays:

```powershell
tar.exe -xf .\gmp-6.3.0.tar.xz
tar.exe -xf .\mpfr-4.2.2.tar.xz
Copy-Item <repo>\libgmp\win64 .\gmp-6.3.0\win64 -Recurse
Copy-Item <repo>\libmpfr\win64 .\mpfr-4.2.2\win64 -Recurse
```

Keep each archive beside its extracted directory. Use a new, initially empty
output directory for every run.

## Mandatory preflight tests

Run from the product repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File prebuilt\write-manifest.ps1 -SelfTest
cmd /d /c "prebuilt\buildall-x86-64.bat --self-test-fail-fast"
echo $LASTEXITCODE
cmd /d /c "prebuilt\buildall-arm64.bat --self-test-fail-fast"
echo $LASTEXITCODE
Select-String prebuilt\buildall-*.bat -Pattern 'FULL64_BIT|FULL_64BIT'
git diff --cached --check
```

Expected:

- manifest self-test exits 0;
- each fail-fast test exits 37;
- no `FULL64_BIT` match;
- both scripts contain `FULL_64BIT=`;
- diff check exits 0;
- `prebuilt\.test-work` is absent afterward.

## Smallest authoritative x64 run

Open an x64 Native Tools environment, then run:

```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" x64
<repo>\prebuilt\buildall-x86-64.bat ^
  --gmp-source "<work>\gmp-6.3.0" ^
  --mpfr-source "<work>\mpfr-4.2.2" ^
  --output "<work>\x64-output" ^
  --entry release_static_noassembly
```

For a development checkout whose staged overlay is intentionally dirty, add
`--allow-dirty-overlay`. Do not use that switch for a release-certification
checkout.

Success gate:

- the runner summary for each library reports zero failed tests;
- exit 0;
- per-entry and aggregate `manifest.json` files exist;
- both libraries have `native_tests_passed`;
- both static libraries report machine `8664`;
- source, overlay, command-log, and artifact hashes are present.

Current verified result on 2026-08-28:

- both test commands returned exit 0, but their colored summaries reported:
  - GMP: `200 overall, 138 succeeded, 61 failed, 1 skipped`;
  - MPFR: `197 overall, 172 succeeded, 18 failed, 7 skipped`;
- the manifest writer parsed those summaries, returned nonzero, and emitted no certifying
  manifest;
- therefore the current x64 run is **not certified**. Diagnose the Windows test-harness/library
  failures before publishing artifacts.

Inspect independently:

```cmd
dumpbin /headers "<work>\x64-output\release_static_noassembly\libgmp.lib" | findstr /i machine
dumpbin /headers "<work>\x64-output\release_static_noassembly\libmpfr.lib" | findstr /i machine
```

## Arm64 build

### Native Windows Arm64 — required for certification

On a machine where `PROCESSOR_ARCHITECTURE=ARM64`, open the native Arm64
developer environment:

```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" arm64
<repo>\prebuilt\buildall-arm64.bat ^
  --gmp-source "<work>\gmp-6.3.0" ^
  --mpfr-source "<work>\mpfr-4.2.2" ^
  --output "<work>\arm64-output" ^
  --entry release_static_noassembly
```

Expected:

- exit 0;
- GMP and MPFR checks execute natively and pass;
- both library manifests say `native_tests_passed`;
- every artifact reports `AA64`.

### AMD64 cross-check — non-certifying

```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" amd64_arm64
<repo>\prebuilt\buildall-arm64.bat ^
  --gmp-source "<work>\gmp-6.3.0" ^
  --mpfr-source "<work>\mpfr-4.2.2" ^
  --output "<work>\arm64-cross-output" ^
  --entry release_static_noassembly
```

On the independently tested AMD64 host this stopped with exit 2 because the
GMP Makefile compiled `colored_print.exe` for Arm64 and then attempted to run
it on AMD64. Treat that result as `not_run_cross`; do not publish or certify
Arm64 libraries from the failed run. A minimal `cl /c`, `lib`, and `link`
probe can still establish toolchain feasibility, but it does not replace the
library build.

## Consumer correctness

For every zero-failure, manifest-certified architecture/configuration:

1. Build a static consumer using both `gmp.h` and `mpfr.h`.
2. Verify a fixed GMP result, for example `2^100`.
3. Verify a bounded MPFR operation, for example `1 < sqrt(2) < 2`.
4. Run the consumer on the matching native architecture.
5. Inspect it with:

```cmd
dumpbin /headers consumer.exe | findstr /i machine
dumpbin /dependents consumer.exe
```

Repeat for DLL entries and verify the expected GMP/MPFR DLL dependencies and
imports. Do not run an Arm64 consumer on AMD64.

## Broader matrix

After the smallest static entries pass, run the named entries needed for the
release:

- `release_static_noassembly`
- `release_static_assembly`
- `release_dynamic_noassembly`
- `release_dynamic_assembly`
- corresponding debug entries
- GMP-only `release_static_assembly_full64bit`
- GMP-only `release_dynamic_assembly_full64bit`

`FULL_64BIT=` is GMP-only and is incompatible with MPFR. The x64 default
remains `ARCH=AVX2`; record any explicit `--arch` override.

Inspect every produced `.lib`, `.dll`, `.exe`, `.obj`, `.pyd`, wheel, archive,
and package. Record machine type, classification, bytes, SHA-256, and runtime
dependencies where applicable.

## Native Arm64 comparison

Use identical inputs on x64 and native Arm64:

- GMP integer exponentiation/multiplication;
- MPFR operations at fixed precision and rounding mode;
- static and DLL consumers;
- assembly and no-assembly entries.

Compare exact numeric outputs and exit codes. Performance and power claims
require repeated measurements on identified physical hardware; do not infer
them from compilation or correctness.

## Failure diagnostics

- **Exit 37:** expected only from `--self-test-fail-fast`.
- **Exit 65:** output directory was not initially empty.
- **Exit 86:** selected compiler target does not match the requested
  architecture.
- **U1045 / 0x800700d8 for `colored_print.exe`:** a target Arm64 helper was
  executed on AMD64. Move the run to native Windows Arm64; do not relabel it as
  a successful cross build.
- **NMake returns 0 but the manifest reports failed tests:** the existing Windows test runner
  can return success even when its final summary contains failures. The manifest is authoritative:
  do not bypass it or publish the libraries. Preserve the logs and diagnose the reported tests.
- **MPFR cannot consume a path with spaces:** the scripts should allocate and
  later remove a checked `subst` alias. Confirm no stale alias remains.
- **Source validation failure:** re-extract the locked archive and recopy the
  exact repository `win64` overlay; never edit the extracted source.
- **Manifest rejection:** correct missing, stale, duplicate, outside-staging,
  wrong-machine, misclassified, or unhashed artifacts rather than bypassing
  validation.

## Lifecycle and cleanup

There is no installer lifecycle for these library artifacts, so clean install,
upgrade, uninstall, service, and registry tests are not applicable.

After evidence is retained:

```powershell
subst
Remove-Item "<work>" -Recurse -Force
Test-Path <repo>\prebuilt\.test-work
git -C <repo> status --short
git -C <repo> diff --cached --check
```

No `subst` mapping may target the deleted work tree, `.test-work` must be
absent, and only the intended product files may remain changed. Promotion must
be a separate atomic operation after all applicable gates pass.
