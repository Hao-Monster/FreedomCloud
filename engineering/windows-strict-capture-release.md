# Windows strict capture release gate

The repository now contains the signed-driver boundary, but release acceptance
is intentionally split from source development:

| Gate | We can do locally | External input required |
| --- | --- | --- |
| WFP callout source and IOCTL contract | Yes; `windows/strict_capture` | None |
| Helper bridge and fail-closed policy | Yes; `services/helper/src/service/driver_bridge.rs` | A Windows client with the driver device for runtime validation |
| Development/test signing | Scripted, isolated only | Permission to use a disposable test certificate on the test VM |
| Production publisher signature | No | Publisher EV/attestation certificate and protected key workflow |
| Microsoft attestation/WHQL | No | Partner Center account and submission rights |
| HLK | Checklist and package preparation | HLK controller, clean Windows 11 client(s), target OS builds |

The current callout deliberately blocks a selected PID only after a broker WFP
filter has been attached, and only until a complete user-mode redirect data
plane is present. The filter installation, TCP/UDP mapping, and Mihomo
lifecycle are still separate implementation gates. Do not install or load the
driver on the development workstation.

## Crash, upgrade and uninstall recovery

The Helper writes a bounded, atomically replaced marker at
`%ProgramData%\FlClashX\strict-recovery.json` before adding a strict filter. A
successful clear removes the corresponding entry only after both IPv4 and IPv6
keys have been deleted. On the next Helper start, entries are replayed as
deterministic filter-key cleanup (including callout keys); malformed or failed
recovery is logged and the marker is retained for the next attempt. The test
collector records only marker presence, target count and SHA-256, never the
executable paths.

The recovery marker is a safety net, not proof of proxy forwarding. Release
acceptance still requires testing Helper/driver/Mihomo restart ordering,
interrupted upgrade, rollback and uninstall on a clean Windows 11 client.
