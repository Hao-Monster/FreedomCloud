# FlClashX v0.2 delivery report

Status: local release candidate; Windows 11 VM acceptance pending.

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

## Release boundary

The current package contains M0 and M1. M2 background Agent, signed Windows WFP
strict mode, signed macOS Network Extension and R-201–R-208 remain separate
milestones. They are not represented as complete by UI switches or YAML-only
promises.

## Known residual risks

- Helper control is still loopback HTTP until the M2 OS-authenticated IPC
  migration. Fixed commands, immutable hashes, protected binaries and Core data
  roots remove the known arbitrary SYSTEM execution/file-access paths; a local
  same-user process can still cause proxy interruption, so this is tracked as a
  Medium local denial-of-service risk.
- Real Windows process attribution, UAC lifecycle, TUN behavior, Zashboard
  coexistence and memory deltas require the supplied Windows 11 VM checklist.
- Strict-mode protocol guarantees are not available before M3/M4.

There are no known Critical or High issues in the delivered M0/M1 attack
surface after the local review. This statement is scoped to inspected code and
executed tests, not a claim of absolute security.
