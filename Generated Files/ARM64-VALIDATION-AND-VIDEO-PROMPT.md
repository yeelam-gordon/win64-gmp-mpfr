# Copilot CLI prompt — native Windows Arm64 validation and Slidecast recording

Run this only on a **native Windows Arm64 machine** after cloning the fork.

## Start

```powershell
git clone --filter=blob:none --no-checkout https://github.com/yeelam-gordon/win64-gmp-mpfr.git
Set-Location .\win64-gmp-mpfr
git sparse-checkout init --no-cone
@'
/*
!/prebuilt/x86-64/
'@ | git sparse-checkout set --no-cone --stdin
git fetch origin
git switch hackathon/arm64-validation-demo
git pull --ff-only
copilot --yolo --experimental --autopilot
```

This keeps the Arm64 prebuilts and all source/demo files while excluding the approximately
80 MB x86-64 prebuilt directory from the working copy and on-demand blob download.

Paste the prompt below into Copilot CLI:

---

You are the native Windows Arm64 validation and demo owner for this repository.
Work autonomously until validation evidence and the Slidecast video package are complete.
Do not amend or rewrite existing commits. Do not push secrets, signing material, downloaded
source archives, intermediate build trees, or package-manager caches.

## Hard preflight

1. Read:
   - `Generated Files\windows-arm-build-test-guide.md`
   - every file under `Generated Files\demo\`
   - `README.md`
   - `prebuilt\sources.json`
2. Invoke the installed skill:
   `C:\Users\yeelam\OneDrive - Microsoft\Documents\.copilot\skills\slidecast`
   and follow its `SKILL.md` literally for the final animated HTML/video render.
3. Prove this is native Windows Arm64:

   ```powershell
   $env:PROCESSOR_ARCHITECTURE
   [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
   ```

   Both must report ARM64. If either does not, stop and report **BLOCKED: not a native
   Windows Arm64 machine**. Do not substitute an x64-emulated process or cross compiler.
4. Confirm Visual Studio C++ tools, native ARM64 MSVC, NMake, Git `patch.exe`, PowerShell,
   `dumpbin`, `curl`, and `tar` are available. Use the repository guide's exact setup.

## Native validation

Current x64 diagnostic baseline: the Windows test runner returned exit 0 while its summaries
reported 61 GMP failures and 18 MPFR failures. The hardened manifest correctly rejected that
run. Do not assume Arm64 will pass or fail the same way; capture its actual summaries and treat
the manifest decision as authoritative.

1. Run the manifest self-test. It must exit 0.
2. Run both fail-fast self-tests. Each must return the exact expected exit code 37.
3. Download GMP 6.3.0 and MPFR 4.2.2 from the locked URLs or an official GNU mirror.
   Accept them only when SHA-512 exactly matches `prebuilt\sources.json`.
4. Extract the archives in a disposable path **outside the repository**, then copy:
   - `libgmp\win64` to the GMP source root as `win64`
   - `libmpfr\win64` to the MPFR source root as `win64`
5. Open the **native ARM64** Visual Studio environment and run:

   ```cmd
   prebuilt\buildall-arm64.bat ^
     --gmp-source "<work>\gmp-6.3.0" ^
     --mpfr-source "<work>\mpfr-4.2.2" ^
     --output "<work>\arm64-output" ^
     --entry release_static_noassembly
   ```

6. Require all of the following before declaring PASS:
   - command exit 0;
   - GMP `check` ran natively and passed;
   - MPFR `check` ran natively and passed;
   - both manifest library statuses are `native_tests_passed`;
   - all produced libraries report machine `AA64`;
   - source/archive/overlay/command-log/artifact hashes are present;
   - no legacy checked-in binary was certified.
7. Build and run a native ARM64 consumer using both libraries. Verify:
   - GMP computes `2^100` exactly;
   - MPFR produces `1 < sqrt(2) < 2`;
   - consumer exit code is 0;
   - `dumpbin /headers` reports `AA64`;
   - record runtime dependencies with `dumpbin /dependents`.
8. If time permits, repeat for assembly and DLL entries. Clearly distinguish mandatory
   `release_static_noassembly` evidence from optional matrix coverage.
9. Do not make performance or power claims unless you create a reviewed benchmark method and
   collect repeatable native measurements. Correctness alone is sufficient.

## Evidence files

Create/update only small text/data evidence under:

`Generated Files\demo\native-arm64-evidence\`

Include:

- `summary.md` — PASS/PARTIAL/BLOCKED, machine model/OS/tool versions, exact commands and exits;
- `manifest.json` — copied final aggregate manifest;
- `artifact-inventory.json` — names, sizes, AA64 machine values and SHA-256;
- `test-results.md` — GMP/MPFR and consumer results;
- `limitations.md` — anything untested and why;
- relevant compact `.log` excerpts, not multi-gigabyte raw build directories.

Never claim success after a failed or skipped native test.

## Update the prepared Slidecast package

1. Use `Generated Files\demo\slidecast\` as the authored package. Do not rebuild the story
   from scratch.
2. Update `evidence-data.json` from the verified native evidence:
   - set native Arm64 status to `passed` only after every mandatory gate above passes;
   - insert actual run ID, test counts/status, artifact sizes, SHA-256, and AA64 values;
   - retain explicit limitations.
3. Replace every visible **PENDING** native-Arm64 placeholder in the deck/storyboard with the
   verified result. If validation is PARTIAL/BLOCKED, keep that status visible and make the
   video an honest diagnostic/demo rather than presenting success.
4. Ensure narration and subtitles say exactly what the evidence proves.
5. Follow Slidecast's pipeline:

   ```powershell
   $slidecastRoot = "C:\Users\yeelam\OneDrive - Microsoft\Documents\.copilot\skills\slidecast"
   Set-Location ".\Generated Files\demo\slidecast"
   pip install -r "$slidecastRoot\scripts\requirements.txt"
   npm --prefix "$slidecastRoot\scripts" install
   python "$slidecastRoot\scripts\build.py" `
     --storyboard .\storyboard.json `
     --deck .\deck.html `
     --package-root . `
     --out .\build
   ```

6. Verify `build\final.mp4` with `ffprobe`, sample rendered frames, and confirm:
   - duration is 2–4 minutes;
   - titles and charts are readable at phone width;
   - subtitles do not cover content;
   - no slide claims more than the native evidence proves;
   - animation cues, narration, and subtitles are synchronized.
7. Copy the final reviewed deliverables to:
   - `Generated Files\demo\final.mp4`
   - `Generated Files\demo\final-subtitles.srt`
   - `Generated Files\demo\final-deck.html` or the complete offline deck folder
   - `Generated Files\demo\native-arm64-evidence\`

## Finish

1. Remove downloaded archives, extracted source trees, temporary build output, `.test-work`,
   transient Slidecast frames/audio, and any temporary `subst` mapping. Keep only final
   evidence and requested deliverables.
2. Run `git status --short` and inspect every changed file.
3. Commit only the native evidence and final demo deliverables:

   ```text
   Record native Windows Arm64 validation and demo

   Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
   ```

4. Push normally to `origin/hackathon/arm64-validation-demo`.
5. Return:
   - native validation verdict;
   - exact commit SHA;
   - final video path and duration;
   - tested matrix;
   - untested items and limitations;
   - whether the Innovation Studio submission text must be updated.

---
