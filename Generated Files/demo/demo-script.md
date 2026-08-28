# Demo script — Fail-closed GMP/MPFR test evidence

**Estimated duration:** 2 minutes 50 seconds
**Format:** terminal, review, and validator evidence; no success video or simulated Arm64 execution
**Core claim:** the verified result is detection of hidden x64 test failures and suppression of certification, not a successful x64 or native Arm64 build.

## Evidence key

- **E1:** Fork review convergence at HEAD `9fad07a3e5255e805374863ec91498499608b5b3`
- **E2:** 13 Copilot review submissions; zero new comments; zero open threads
- **E3:** Upstream draft PR: <https://github.com/developer-corner/win64-gmp-mpfr/pull/1>
- **E4:** Current native x64 test summaries and validator result
- **E5:** Existing project design and Arm64 runbook evidence

## Timeline

| Time | Visual | Exact narration | Evidence |
|---|---|---|---|
| 00:00–00:13 | Title and evidence contract | GMP and MPFR provide arbitrary-precision arithmetic used across CAD, geometry, security, and scientific software. For Windows Arm, the challenge is not merely producing binaries. It is proving which source was built, which tests ran, and whether the result deserves certification. | E5 |
| 00:13–00:26 | Existing Arm64 paths and prior vcpkg support | The project first corrected its premise. Community Arm64 paths and earlier vcpkg support already existed, so this work does not claim first-time Windows Arm support. The objective became a fail-closed evidence path rather than a new platform-support claim. | E5 |
| 00:26–00:40 | Trust-gap checklist | The trust gaps were concrete: weak source identity, hidden command failures, inconsistent full-64-bit configuration, and no reliable binding between test outcomes and a certifying manifest. Existing binaries and earlier apparent successes could not settle those questions. | E5 |
| 00:40–00:54 | Review loop, HEAD, and draft PR | The fork review loop then converged on HEAD 9fad07a3e5255e805374863ec91498499608b5b3. Thirteen Copilot review submissions produced zero new comments and left zero open threads. The corresponding upstream contribution is draft pull request number one. | E1–E3 |
| 00:54–01:07 | Self-test command results | The provenance and fail-fast self-tests pass. Those checks establish that the machinery can reject controlled errors and handle its manifest rules. They do not prove that GMP or MPFR passed their native test suites. | E4 |
| 01:07–01:20 | Runner exit code beside failing summaries | Full native x64 source builds reach both test suites. However, the existing Windows test runner returns exit zero even when its own summaries contain failures. Exit status alone therefore creates a false-success signal. | E4 |
| 01:20–01:32 | GMP summary | For GMP, the parsed summary reports 200 tests overall: 138 succeeded, 61 failed, and one skipped. This is not a passing GMP test result, even though the surrounding runner returned zero. | E4 |
| 01:32–01:44 | MPFR summary | For MPFR, the parsed summary reports 197 tests overall: 172 succeeded, 18 failed, and seven skipped. This is also not a passing MPFR test result. | E4 |
| 01:44–01:57 | ANSI stripping and validator rejection | The new validator strips ANSI control sequences, parses both summaries, and rejects any nonzero failure count. On this evidence it exits nonzero and emits no certifying manifest. That detection is the verified project result. | E4 |
| 01:57–02:10 | Superseded evidence crossed out | The x64 gate is therefore unresolved, but now diagnosed honestly. Earlier artifact sizes, hashes, native-tests-passed labels, and consumer checks must not be presented as certification evidence from a passing build. | E4 |
| 02:10–02:21 | Draft PR page | The contribution is visible for review in upstream draft pull request one at developer-corner slash win64-gmp-mpfr. Draft status is not acceptance, merge, signing, release, or publication. | E3 |
| 02:21–02:34 | Claim-boundary panel | No performance, power, signing, publication, certification, or downstream-unblocking claim is supported. The value delivered is stricter evidence handling: a misleading zero exit can no longer create a certifying manifest. | E4 |
| 02:34–02:50 | Two unresolved gates | Two gates remain. First, diagnose and fix the x64 test failures, then obtain clean summaries through the validator. Second, run the locked build and test process on a native Windows Arm64 machine. Until both gates close, x64 certification is unresolved and native Arm64 proof remains pending. | E4–E5 |

## Demo close

End with both unresolved gates visible: **x64 test diagnosis / clean validation** and **native Arm64 build and tests**.
