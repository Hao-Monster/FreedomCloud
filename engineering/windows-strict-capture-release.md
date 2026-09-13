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

The current driver deliberately blocks a selected PID until a complete
user-mode redirect data plane is present. This prevents a selected application
from silently escaping to a direct connection while the TCP/UDP mapping and
Mihomo lifecycle work is still under validation. Do not install or load it on
the development workstation.
