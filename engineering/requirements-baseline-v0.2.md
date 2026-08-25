# FlClashX requirements baseline v0.2

Status: approved for phased implementation on 2026-08-26.

This baseline separates product acceptance from release scope. Accepting a
requirement means it belongs to the product roadmap; it does not mean that a
kernel driver, Apple entitlement, signing certificate, or production rollout
can be completed inside the connections UI pull request.

## P0: connections stability and performance

| ID | Requirement | Delivery rule |
|---|---|---|
| R-001 | Performance is the first goal. | Every hot path needs bounded memory, non-overlapping work, and a measurable budget. |
| R-002 | Reduce desktop resident memory. | Measure against an idle baseline and synthetic 1,000-active/300-closed workloads; do not use a single Task Manager screenshot as proof. |
| R-003 | Migrate the complete KoalaClash connections experience. | Process grouping, application icon, per-process rate, details, settings, filtering, sorting, pause, close, and closed history. |
| R-004 | Preserve classic per-connection mode. | All metadata, rule, proxy chain, target and close actions remain available. |
| R-005 | Resolve Windows 11 process attribution. | Edge traffic in the VM must show the real network process when Mihomo supplies process metadata; otherwise diagnostics must identify the missing layer. |
| R-006 | Provide diagnostics in test builds. | Cover runtime, core response, decode, polling and attribution state without recording connection metadata. |
| R-007 | Bound and redact diagnostics. | No subscription URL, secret, authorization header, host, IP, process path or username; bounded file size and exportable artifacts. |
| R-008 | Avoid repeated first-run UAC repair. | Elevation is allowed once for install/repair. Normal later starts use the existing service. Portable packages may require one initial service registration. |
| R-009 | Do not regress Zashboard. | Zashboard remains an independent External Controller consumer; connections UI state must not own its lifecycle or data. |
| R-010 | Preserve current Active/Log product behavior. | Frozen: no redesign, deletion, or inferred decision in this baseline. |
| R-011 | Provide a Windows portable test package. | Include build identity, diagnostic instructions and VM acceptance checklist. |
| R-012 | Use disciplined Git history. | `codex/` branches, atomic commits, task-only staging, no unrelated user changes, no push or merge without explicit authorization. |

## P1: per-application proxy

| ID | Requirement | Approved behavior |
|---|---|---|
| R-101 | Independent per-application proxy feature. | Enhances rather than replaces domain/IP rules. |
| R-102 | Select installed or recently observed applications. | Show display name, icon, canonical path and actual network child processes. |
| R-103 | Application policies. | Inherit rules, force a proxy/policy group, force DIRECT, or block. |
| R-104 | Preserve existing domain/IP routing. | Unselected applications behave exactly as before. |
| R-105 | Application policy precedence. | Explicit force-proxy/direct/block precedes ordinary domain/IP routing for that application. |
| R-106 | Application-family identity. | Model Electron helpers, renderers, language servers, Node and other child processes without unsafe broad wildcards. |
| R-107 | Protocol coverage. | TCP, UDP, IPv4, IPv6, QUIC/HTTP3 and DNS are part of strict-mode acceptance. |
| R-108 | Strict-mode contract. | Proxy or block; never silently fall back to the physical network. |
| R-109 | Non-strict mode. | Compile to Mihomo PROCESS-PATH/PROCESS-NAME rules. |
| R-110 | Windows strict capture. | Signed WFP callout/connect-redirect implementation; no DLL injection. |
| R-111 | macOS strict capture. | Network Extension with signing-identifier/bundle-identifier identity; no injection. |
| R-112 | DNS/domain restoration. | Reuse Mihomo DNS/Fake-IP and preserve domain-rule evaluation. |
| R-113 | Application diagnostics. | Explain actual process, capture state, matched policy, route and failure reason. |
| R-114 | Background enforcement. | Policies do not depend on the connections page or Flutter UI being alive. |
| R-115 | Upgrade-safe identity. | Migrate paths only after publisher/signature identity verification. |
| R-116 | Recovery and uninstall. | Crash, shutdown, upgrade and uninstall remove filters/routes and restore safe state. |

Strict-mode guarantee:

> For TCP/UDP IPv4/IPv6 traffic that the operating system can attribute to a
> selected application, FlClashX either forwards the flow through the selected
> policy or blocks it. It never intentionally permits direct fallback.

Delegated system services, WSL/VM/container traffic, kernel-originated traffic,
protected processes and unrelated brokers are outside this identity guarantee
until their actual network identity is selected.

## P1: lightweight background architecture

| ID | Requirement | Approved behavior |
|---|---|---|
| R-120 | Close UI while keeping proxy operation. | Core, TUN and policies may continue under the Agent. |
| R-121 | Reattach UI. | Reopening attaches to the existing Agent/Core without connection interruption. |
| R-122 | Three exit actions. | Close UI, stop proxy, and fully exit are distinct operations. |
| R-123 | UI does not own Core lifecycle. | A per-user Agent owns state; the privileged service exposes only narrow operations. |
| R-124 | No hidden UI polling. | A hidden/closed UI stops connection-list, icon and high-frequency refresh work. |

## P2: accepted roadmap

| ID | Feature | Order |
|---|---|---:|
| R-201 | Enhanced tray for profile, group, node, virtual network card, rates and latency. “Virtual network card” is the only user-facing name for Mihomo TUN. | 1 |
| R-202 | Effective configuration diff: subscription, overrides and actual Core config. | 2 |
| R-203 | One-click health check and redacted diagnostic bundle. | 3 |
| R-204 | PAC system-proxy mode. | 4 |
| R-205 | Network-environment automation. | 5 |
| R-206 | Signed in-app update with progress, verification and rollback. | 6 |
| R-207 | Rule editor with YAML synchronization, effective diff, undo and restore. | 7 |
| R-208 | Jump from a connection/policy to its active group and node. | 8 |

System proxy and virtual network card are separate ingress modes. They can
coexist technically, but the normal UI treats them as mutually exclusive to
avoid double capture, ambiguous attribution and DNS/restore complexity.

## Explicit non-goals

The following are excluded from implementation: Antigravity `version.dll`
integration, generic DLL hijacking or remote-thread injection, floating traffic
window, Electron-style remote CSS, arbitrary core switching, multi-core support,
running the entire UI elevated, stopping Core whenever the network disappears,
and unbounded history/log/icon caches.
