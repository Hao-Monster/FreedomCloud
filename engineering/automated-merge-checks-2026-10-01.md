# PR 53 automated merge checks

User authorization supersedes the earlier source-only prohibition for automated
merge checks. Real-device, WFP traffic, macOS deployment and business acceptance
remain user-owned; no package, signing, deployment or device test was performed.

## First run and repairs

CI run 36815741987 on a003c5a failed. Local tests reproduced missing ResultExt
imports in effective configuration and rule editor views. Both views now import
the existing extension instead of inventing a new result API. Two UDP tests
expected ordinary group routing; the approved strict-only routing contract now
requires generation-scoped aliases and authenticated user metadata. Updated
assertions retain exact destination/payload/reply/replay/collision checks. New
route tests reject DIRECT, cycles, wrong user/generation/listener/source and
revoked routes, and accept the selected protocol leaf. No test was skipped.

## Local repaired-source results

- Flutter 3.47.4, Windows: `flutter test --no-pub`: PASS, 95 tests, exit 0.
- Go 1.25.13, Windows: `go test ./...` in core: PASS, exit 0; core/state has no tests.
- Test-M3PackageTools.ps1: PASS.
- Test-M3ManifestAssemblyOrder.ps1: PASS.
- Test-M3EvidenceValidator.ps1: PASS.
- `git diff --check`: PASS.

CI uses Flutter 3.41.7 and Go 1.26.0; local success alone is not its evidence.
The PR check links on the final head are authoritative for merge eligibility.
These checks do not compile or qualify the macOS native extension, exercise a
loaded Windows WFP driver or prove real network leak prevention. Coverage was
not collected and no coverage percentage is claimed.
