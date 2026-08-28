# Impact and claim evidence

## Current claim map

| Demo claim | Verified value | Limitation |
|---|---|---|
| Fork review convergence | HEAD `9fad07a3e5255e805374863ec91498499608b5b3` after 13 Copilot review submissions, zero new comments, and zero open threads | Review convergence is not upstream acceptance or technical certification. |
| Upstream contribution | Draft PR <https://github.com/developer-corner/win64-gmp-mpfr/pull/1> | Draft only; not merged, signed, released, or officially published. |
| Manifest and fail-fast self-tests | Pass | These validate the evidence machinery, not GMP/MPFR library correctness. |
| Native x64 build reach | Full source builds reach both test suites | Reaching the suites is not passing them. |
| Existing Windows runner behavior | Returns exit `0` while summaries contain failures | Exit code cannot be used alone as certification evidence. |
| GMP x64 summary | 200 overall; 138 succeeded; 61 failed; 1 skipped | Unresolved failing test suite. |
| MPFR x64 summary | 197 overall; 172 succeeded; 18 failed; 7 skipped | Unresolved failing test suite. |
| New validator | Strips ANSI, parses summaries, rejects nonzero failures, exits nonzero | Correct fail-closed result for the current summaries. |
| Certifying manifest | Not emitted | This absence is intentional and verified. |
| Native Arm64 | `PENDING` | Must run on a native Windows Arm64 machine. |

## Superseded claims

The following must not appear as current evidence:

- GMP or MPFR x64 tests passed.
- `138` or `172` represents complete passing suites.
- Any artifact has `native_tests_passed` or equivalent certification status.
- Consumer correctness was established from certified artifacts.
- Earlier artifact byte counts or SHA-256 hashes are final evidence.

## Impact interpretation

- The verified project result is **detection**: a misleading runner exit code can no longer produce a certifying manifest.
- x64 certification remains unresolved pending diagnosis and clean test summaries.
- Native Arm64 proof remains pending and requires a native Arm64 machine.
- Review convergence and a draft upstream PR improve reviewability but do not establish acceptance, publication, signing, or release.
- No performance, power, certification, or downstream-unblocking claim is supported.

## Confidence

**High confidence in the review state, parsed x64 summaries, and validator rejection. Medium confidence in platform readiness because x64 failures remain unresolved and native Windows Arm64 execution has not occurred.**
