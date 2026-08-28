# Shot list

| Shot | Time | Capture | On-screen emphasis |
|---:|---|---|---|
| 1 | 00:00–00:13 | Repository title and evidence contract | “Binaries are not proof” |
| 2 | 00:13–00:26 | Existing Arm64 paths and prior vcpkg support | “Support already existed” |
| 3 | 00:26–00:40 | Source identity, failure propagation, configuration, manifest binding | “Trust gaps” |
| 4 | 00:40–00:54 | Fork HEAD, review submissions, open-thread state, draft PR | HEAD `9fad07a…`; 13 reviews; 0 comments; 0 threads |
| 5 | 00:54–01:07 | Manifest and fail-fast self-test output | “Machinery passes; libraries not certified” |
| 6 | 01:07–01:20 | Runner exit 0 beside parsed failure summaries | “Exit 0 ≠ test success” |
| 7 | 01:20–01:32 | GMP summary | 200 overall / 138 succeeded / 61 failed / 1 skipped |
| 8 | 01:32–01:44 | MPFR summary | 197 overall / 172 succeeded / 18 failed / 7 skipped |
| 9 | 01:44–01:57 | Validator stages | Strip ANSI → parse → reject failures → no manifest |
| 10 | 01:57–02:10 | Superseded artifact claims | No final hashes, sizes, certification, or consumer proof |
| 11 | 02:10–02:21 | Upstream draft PR page | Draft PR #1; not accepted or published |
| 12 | 02:21–02:34 | Claim-boundary panel | No performance, power, signing, publication, certification, or unblock claim |
| 13 | 02:34–02:50 | Two-gate checklist | x64 diagnosis unresolved; native Arm64 pending |

## Capture rules

- Show only the current summaries and validator outcome.
- Keep the runner’s exit zero visually adjacent to the nonzero failure counts.
- Never show a certifying x64 manifest; the verified validator emits none.
- Do not reuse old artifact sizes, hashes, `native_tests_passed`, or certified consumer claims.
- Keep **x64 diagnosis unresolved** and **native Arm64 pending** visible.
- Do not imply draft PR acceptance, signing, release, publication, performance, power, or downstream unblocking.
