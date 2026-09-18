# FreedomCloud M4 macOS strict mode

Status: **Blocked until M3 exit criteria and Apple prerequisites are complete**

GitHub milestone: [FreedomCloud M4 macOS strict mode](https://github.com/Hao-Monster/FreedomCloud/milestone/2)

M4 is a separate post-M3 milestone. It must not be used as evidence for the
Windows strict WFP release gate.

## Scope

- Signed macOS Network Extension capture.
- Bundle/signing-identifier identity and bounded child-process handling.
- Authenticated app-to-extension control and recovery state.
- Crash, sleep/resume, upgrade, rollback and uninstall cleanup.
- Supported macOS integration, signing and notarization evidence.

## Dependencies and blockers

- M3 signed Windows driver, Broker lifecycle and Windows 11 qualification must
  remain complete and separately evidenced before M4 release claims.
- Apple Developer team, Network Extension entitlement, signing identity and
  notarization credentials are external prerequisites.
- M4 acceptance requires signed macOS test artifacts and real host evidence;
  source interfaces, mocks and unsigned local builds are not acceptance proof.

## Governance

Every M4 feature gets its own GitHub issue and focused PR. M4 work targets the
M4 milestone and must not be attached to the M3 Windows evidence ledger.
