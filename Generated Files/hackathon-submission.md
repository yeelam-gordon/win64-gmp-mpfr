# Microsoft Global Hackathon 2026 — Project Submission

Event: Microsoft Global Hackathon 2026 (eventId `571ba5dc6cf9`)
Form: default submission type, version 13
Submission URL: https://innovation-studio.microsoft.com/events/hackathon2026/submissions/projects
Project ID: `proj-19313284-b14c-431e-a6f6-ac95ae7532aa`
Created project: https://innovation-studio.microsoft.com/events/hackathon2026/submissions/projects/proj-19313284-b14c-431e-a6f6-ac95ae7532aa
Current status: Saved; final submission requires a video of no more than 2:00.

> **Duplicate prevention:** Check `hackathon-project.json` and report this
> existing project before attempting to create another one.

> Copy each block into the matching field. Required manual actions are listed at the end.

---

## Step 1 — Basics

### Project Name *(required, text, ≤140 chars, field `fixed-title`)*
Trustworthy GMP + MPFR Builds for Windows Arm64

### Tagline *(required, text, ≤160 chars, field `fixed-tagline`)*
Turn existing Windows Arm64 math-library support into a fail-closed, reproducible build pipeline with locked sources, tests, and verifiable artifacts.

### Executive Challenge *(required, dynamic single select)*
**Manual selection required.** Search the live catalog for the closest match to:

- Windows on Arm / Copilot+ PCs
- Open Source
- Developer productivity or developer tools
- Software supply-chain security

### Topic Challenges *(optional, dynamic picker, up to 5)*
Suggested searches: **Windows**, **Open Source**, **Security**, **Developer Experience**, and **Arm64**.

### Video *(required, video)*
**Manual upload required.** Use the checked-in Arm64 validation/recording prompt and
`Generated Files\demo\` assets after the fork is synchronized to a native Windows Arm64
machine. Show:

1. The original build-integrity defects.
2. Locked source and overlay verification.
3. Fail-fast negative tests.
4. Native Windows Arm64 GMP and MPFR build/test output.
5. The generated architecture and artifact manifest.

Do not claim native Arm64 completion until step 4 has actually passed on that machine.

### Description *(optional, markdown, field `fixed-description`)*
```markdown
## Why this matters

GMP and MPFR are foundational arbitrary-precision math libraries used by CAD, geometry,
security, and scientific software. A feature-aware vcpkg scan found at least **15 direct
non-self GMP consumers** and **7 direct non-self MPFR consumers**. Indexed conda-forge
searches found **142 GMP** and **55 MPFR** feedstock text hits.

These are conservative ecosystem lower bounds, not unique-user counts or a complete
transitive dependency graph. They still show why release integrity in these libraries
has leverage: one mislabeled or unverified math binary can flow into many downstream
Windows applications.

Windows Arm64 support already existed in both the community MSVC recipe and vcpkg, but
the community release process could not reliably prove what was built.

The scripts contained real trust defects:

- a misspelled `FULL64_BIT` option produced binaries whose `full64bit` label could not be trusted;
- failed build, test, or copy commands could be hidden by later successful commands;
- source archives, extracted source, and the exact build overlays were not cryptographically bound;
- existing binaries could be hashed without proving they came from the current run;
- native test status could be inferred without structured evidence that tests ran;
- common Windows paths containing spaces or `!` could break command execution or provenance.

## What we built

We redirected the project away from duplicating already-merged Arm64 implementation work and
created a five-file trust-hardening change:

1. Fail-fast x64 and Arm64 build orchestration with exact exit-code preservation.
2. Locked GMP 6.3.0 and MPFR 4.2.2 source metadata.
3. Full source/archive/overlay identity verification before certification.
4. Structured command and test records.
5. Fail-closed manifests containing artifact type, architecture, size, and SHA-256.
6. Explicit separation of native execution from cross-compilation evidence.
7. Honest documentation that refuses to certify legacy or mislabeled binaries.

## Verified result

- Manifest self-tests pass.
- Both controlled fail-fast tests return the exact expected exit code, 37.
- Fresh native x64 GMP and MPFR source builds reached both Windows test suites.
- The existing test runner returned exit 0 even though its summaries reported **61 GMP
  failures** and **18 MPFR failures**.
- The new certification gate detected those summaries, returned a failure, and emitted **no
  certifying manifest**. This is the verified result: failed tests can no longer look successful.
- Minimal Arm64 object, library, and executable probes report machine type `AA64`.
- The fork PR completed 13 Copilot review rounds and converged on the current reviewed commit
  with zero new comments and zero open threads.

## Windows Arm64 gate

This x64 development machine cannot honestly complete native Arm64 runtime validation. The
remaining step is to synchronize the fork to a native Windows Arm64 machine or runner, execute
the checked-in validation prompt, and record the resulting demo. Official signing and release
publication remain maintainer-owned and are not required for hackathon completion.

## Ecosystem leverage

A current feature-aware vcpkg scan gives lower bounds of at least 15 non-self GMP consumers
and at least 7 non-self MPFR consumers. Earlier indexed conda-forge searches found 142 GMP and
55 MPFR feedstock text hits. These are direct/indexed lower bounds, not a complete transitive
dependency graph and not a claim that all consumers were previously blocked.

## Links

- Fork review PR: https://github.com/yeelam-gordon/win64-gmp-mpfr/pull/1
- Upstream draft PR: https://github.com/developer-corner/win64-gmp-mpfr/pull/1
- Community project: https://github.com/developer-corner/win64-gmp-mpfr
- vcpkg: https://github.com/microsoft/vcpkg
```

### Keywords *(optional, tags, field `default-keywords`)*
Windows on Arm, Arm64, GMP, MPFR, C++, MSVC, Open Source, Reproducible Builds, Supply Chain Security, Release Engineering

### Recruiting *(optional, roles, field `default-open-roles`)*
Windows Arm64 hardware tester; C/C++ release engineer; open-source maintainer.

---

## Step 2 — Additional information

### Hacking On *(required, keywords, field `custom-1783618182153-76oo1g`)*
C++, MSVC, Windows on Arm, GMP, MPFR, PowerShell, Batch, Reproducible Builds, Provenance

### Who is this for? *(required, select, field `custom-1783618242924-abtdb0`)*
**Developers**

### Venue *(required, select, field `custom-1783618430773-p04el3`)*
**Greater China Region - Shanghai**

### Problem or opportunity statement *(required, text, field `custom-1783618909399-eestbp`)*
At least 15 non-self vcpkg ports consume GMP and at least 7 consume MPFR (non-exclusive lower bounds), but the Windows build could not prove locked sources, architecture, options, or successful tests. We make every claim verifiable and stop failed runs from looking successful.

### Writing Code *(required, select, field `custom-1783618919359-iurwr8`)*
**Yes**

### If you see this project as a feature within an existing Microsoft product or service, please identify the product/service. *(optional, text, field `custom-1784047582479-jtlpdb`)*
N/A — this is an open-source Windows Arm64 build and software-supply-chain project.

### Briefly describe what you made and how you made it *(optional, textarea, field `custom-1784047418953-o01cra`)*
We first verified that the proposed Arm64 implementation work was already solved upstream, then narrowed the project to real release-integrity defects. We fixed the Windows build scripts, locked and verified source archives plus exact overlays, hardened tool resolution, and added structured test evidence plus architecture-aware artifact manifests. The pipeline exposed 61 GMP and 18 MPFR failures that the existing runner returned as exit 0, then correctly refused certification. Native Arm64 execution is the final hardware-runner gate and has an executable checked-in runbook.

### Code repository *(optional, URL, field `custom-1784584386445-zqikfv`)*
https://github.com/developer-corner/win64-gmp-mpfr/pull/1

---

## Outstanding items you must complete manually

1. **Executive Challenge** — select the closest live catalog entry.
2. **Topic Challenges** — optionally select up to five relevant entries.
3. **Native Arm64 validation** — synchronize the fork/validation branch to a Windows Arm64
   machine and run the checked-in Copilot CLI prompt.
4. **Video** — generate and review the Slidecast recording only after native Arm64 results exist.
5. **Human review** — the upstream PR is intentionally a draft because the security-sensitive
   pipeline is large and the current Windows tests still fail.
6. **Submit** — upload the video and click Submit in the authenticated Innovation Studio session.
