# FreedomCloud P2 roadmap

Status: **Post-M3 roadmap; no M3 acceptance credit**

GitHub milestone: [FreedomCloud P2 roadmap](https://github.com/Hao-Monster/FreedomCloud/milestone/3)

P2 work is independent from M3 Windows strict readiness. Each item requires a
separate issue, focused PR, tests, user-visible acceptance and rollback notes.

## Ordered work items

| Order | Requirement | Scope |
|---:|---|---|
| 1 | R-201 | Enhanced tray for profile, group, node, virtual network card, rates and latency. |
| 2 | R-202 | Effective configuration diff for subscription, overrides and actual Core config. |
| 3 | R-203 | One-click health check and redacted diagnostic bundle. |
| 4 | R-204 | PAC system-proxy mode. |
| 5 | R-205 | Network-environment automation. |
| 6 | R-206 | Signed in-app update with progress, verification and rollback. |
| 7 | R-207 | Rule editor with YAML synchronization, effective diff, undo and restore. |
| 8 | R-208 | Jump from a connection or policy to its active group and node. |

## Dependencies and blockers

- M3 signed Windows gates and current runtime defects remain prerequisites for
  any release claim that depends on strict traffic behavior.
- R-206 additionally requires release-signing public keys and an offline
  private-key process; an unsigned updater is not an implementation shortcut.
- PAC, TUN and strict capture must retain separate ingress ownership and
  explicit DNS/restore behavior to prevent double capture.

## Non-goals

No P2 item changes M3 exit criteria, creates strict WFP evidence, or silently
becomes part of an M3 release candidate.
