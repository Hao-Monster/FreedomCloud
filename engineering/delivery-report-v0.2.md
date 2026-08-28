# FlClashX v0.2 delivery report

Status: M0/M1/M2 local release candidate; Windows 11 VM acceptance pending.

## Artifact

- Runtime/package source commit:
  `02cd7405aa4a0ef5bfdfc2964b9c20b5bff84e5f`
- Installer: `FlClashX-windows-amd64-setup.exe`
  - Size: 37,122,321 bytes
  - SHA-256: `8A4B327C45C488CE0AAC57F18B1A8C434B1B1B9008A3AD90E70508CB42DA6F7A`
  - Authenticode: `NotSigned` (local VM test build only)
- Portable archive: `FlClashX-windows-amd64.zip`
  - Size: 53,497,773 bytes
  - SHA-256: `D48F23A08F8B357CEAC0561CD65EAF4C2D1FE824598F910C6AE42BF51B068FED`
- Packaged executable SHA-256:
  - `FlClashX.exe`: `0BB86AAEAF428448039974843C29246A964ABB2B8D0F6496CDD72ED8D47D50E6`
  - `FlClashAgent.exe`: `C195F0BF44F011FE0B6887FC83BFCC6FE07DDB4D6ADAF43D2EFDB8FBAD025405`
  - `FlClashCore.exe`: `784A0E8215142C8ADE616BB6E27004C013446BC0D115DE60B125A9D9D169F835`
  - `FlClashHelperService.exe`: `D553EB5ADC3F1DDBAE051FC6588EEB4B3746EBEF2F74A3945C154B1FEDFB45AA`

The archive table was checked for UI, Agent, Core, Helper, Flutter data,
`BUILD-INFO.txt` and `WINDOWS-VM-CHECKLIST.md`. The embedded build identity was
read back and matches the source commit above. Inno Setup 6.7.3 compiled the
installer and its log confirms those same files were compressed. The installer
was not executed on the development host because installation changes service
and network-related state; execution remains a VM acceptance item.

## Delivered scope

- Process-centric and classic connection views share one bounded snapshot
  pipeline. Process cards include application icons, connection counts, totals,
  instantaneous rates and drill-down details.
- Search, filtering, sorting, pause/resume, close-one, close-filtered, bounded
  closed history, settings and privacy-safe diagnostic export are implemented.
- Desktop process view forces Mihomo process discovery to `always` without
  changing classic-view semantics. Missing Core process metadata is not
  fabricated by source-IP grouping.
- Non-strict per-application `INHERIT`, policy-group, `DIRECT` and `REJECT`
  actions compile to bounded PROCESS-PATH rules ahead of ordinary domain/IP
  rules. Unselected applications retain the existing rule behavior.
- Hidden Connections UI performs zero polling. Icon caches, decoded Flutter
  images, closed history and diagnostic files have explicit limits.
- Windows Helper setup is idempotent. SYSTEM binaries run from a protected
  Program Files service directory, the Core allow-list is immutable, arbitrary
  file/config roots are rejected and unsigned privileged Core updates are off.
- Zashboard and Active/Log ownership are unchanged.
- A persistent per-user Agent now owns Core lifecycle. UI close/restart detaches
  without listener rebuild; stop proxy and full exit are distinct operations.
- Agent/UI and Agent/Core use versioned authenticated bounded IPC. Only one UI
  session is active, confirmed mutations enter a 128-entry journal, crash retry
  is bounded and lifecycle results are not dropped under stream pressure.
- Helper start and stop both require a separate per-user 256-bit credential;
  requests, paths and the embedded Core digest remain bounded/restricted.

## Release boundary

The current package contains M0, M1 and M2. Signed Windows WFP strict mode,
signed macOS Network Extension and R-201–R-208 remain separate milestones. They
are not represented as complete by UI switches or YAML-only promises.

## Known residual risks

- Agent and Helper control use random per-user capabilities over bounded
  loopback IPC. Fixed commands, immutable hashes, protected binaries and Core
  data roots remove the known arbitrary SYSTEM execution/file-access paths. A
  malicious process already running as the same user can read the user's Helper
  credential and interrupt the proxy, so this remains a Medium local
  denial-of-service risk; ACL-restricted named pipe/XPC transport is future
  defense in depth.
- Real Windows process attribution, UAC lifecycle, TUN behavior, Zashboard
  coexistence, UI detach traffic continuity, uninstall cleanup and memory deltas
  require the supplied Windows 11 VM checklist.
- Strict-mode protocol guarantees are not available before M3/M4.

There are no known Critical or High issues in the delivered M0/M1/M2 attack
surface after the local review. This statement is scoped to inspected code and
executed tests, not a claim of absolute security.
