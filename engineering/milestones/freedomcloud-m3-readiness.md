# FreedomCloud M3 readiness milestone

Status: Open
Owner: `development`
Baseline: `3b7bfcd` (`codex/koala-connections`)
Created: 2026-09-19

This milestone records the nine open workstreams found during the read-only
project audit. It is the source-of-truth checklist for the FreedomCloud
repository while the Windows strict WFP path is being prepared. Existing
uncommitted work remains outside this milestone until it is reviewed and
assigned to a focused commit.

## Goals

1. **Workspace provenance and clean baseline**
   - Inventory the existing tracked and untracked changes.
   - Assign every change to a focused commit or explicitly retain it as a
     local experiment.
   - Keep reproducible builds tied to a committed SHA.

2. **Reproducible Windows package pipeline**
   - Build the portable and installer packages from a clean committed checkout.
   - Embed the exact source SHA, package type, artifact hashes and verification
     instructions.
   - Ensure ordinary packages never claim or silently include strict WFP.

3. **Visual Studio and WDK toolchain**
   - Restore a working x64 `WindowsKernelModeDriver10.0` toolset.
   - Reproduce the pinned WDK/SDK Release build with `/W4 /WX`,
     DriverMinimumRules and ApiValidator.
   - Preserve the current failure evidence until a clean rebuild passes.

4. **Trusted signing and manifest chain**
   - Obtain the authorized driver-signing/HLK path.
   - Sign the driver, Agent, Core and Broker with the approved identities.
   - Generate a manifest whose build ID, file hashes and publisher hashes match
     the staged files; reject unsigned and test-placeholder inputs.

5. **Strict Broker service lifecycle**
   - Install the Broker as the protected LocalSystem service with verified SCM
     image paths and recovery-directory ACLs.
   - Verify driver service/device opening, IOCTL identity handshake, Agent
     activation and fail-closed cleanup.
   - Capture service and event-log evidence for start, stop, restart and
     uninstall.

6. **Windows 11 strict traffic qualification**
   - Run the signed bundle in the isolated Windows 11 VM matrix.
   - Qualify TCP, UDP, IPv4, IPv6, DNS, QUIC/HTTP3, Edge, Electron,
     connected UDP and `sendto` flows.
   - Test crash, sleep/resume, network switch, upgrade, rollback, uninstall,
     Driver Verifier, pool usage and 30-minute resource stability.

7. **Current runtime defects**
   - Resolve the repeated Helper/UAC repair results (`42` and `5`) and prove
     one-time repair behavior.
   - Diagnose the Agent UI session reset (`10054`).
   - Identify and repair the one unavailable per-application target.
   - Repair the remote rule-provider TLS/EOF failures where the endpoint is
     under project control.
   - Migrate `global-client-fingerprint` to the current Mihomo field.

8. **Branch, PR and CI governance**
   - Use `main` for reviewed integration and `development` for ongoing work.
   - Keep every functional change in a focused branch and pull request.
   - Require source SHA, package provenance, relevant tests and known gaps in
     every PR; do not merge strict capability claims without VM evidence.
   - Enable CI on the development branch before calling a milestone complete.

9. **Post-M3 roadmap control**
   - Keep macOS Network Extension (M4) and P2 items R-201 through R-208
     separate from M3 acceptance.
   - Do not start release claims for M4/P2 until M3's signed Windows gates,
     current runtime defects and repository governance are closed.

## Completion gate

The milestone is complete only when all nine goals have linked commits, review
evidence and, where applicable, Windows 11 VM artifacts. A visible strict
button, YAML policy or unsigned local package is not evidence of strict WFP
acceptance.

## Repository workflow

- `main`: reviewed integration and release candidates.
- `development`: local development branch and integration queue.
- `codex/*`: short-lived focused work branches; each must open a PR into
  `development`.
- PRs merge into `main` only after the required checks and artifact provenance
  are recorded.
- Never force-push shared branches. Never clean or reset unrelated local work
  as part of milestone work.
