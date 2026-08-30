# FlClashX M3 Windows 11 VM qualification checklist

This checklist applies only to a Microsoft-signed M3 qualification bundle. Do
not enable test signing or load the strict driver on a development workstation.
Take a clean VM snapshot before starting and restore it after evidence export.

## Package and platform

1. Run `Invoke-M3VmPreflight.ps1` elevated. It must confirm every package hash,
   every Authenticode/catalog signature, the package build ID and VM identity.
2. Record Windows edition/build, Secure Boot and HVCI state. Repeat the release
   gate with Secure Boot and HVCI enabled.
3. Confirm the driver file, loaded kernel service and Broker manifest expose the
   same build identity. Reject any mismatch before opening strict admission.

## Lifecycle and failure containment

4. Install into the fixed Program Files layout and provision the recovery
   directory with non-inheriting LocalSystem/Administrators ACLs.
5. Start/stop/restart Broker and driver 100 times with Driver Verifier enabled.
   No unload hang, bugcheck, verifier finding, stale WFP object or leaked handle
   is acceptable.
6. Kill Broker, Agent and Core independently during prepare, commit, active UDP,
   lease renewal and shutdown. Selected traffic must block; it must never fall
   back to a direct connection.
7. Exercise pending Direct-I/O cancellation, active classify/flow-delete races,
   lease expiry and service stop. Unregister and flow/injection drain outcomes
   must be observable and bounded.

## Traffic correctness

8. Test TCP and UDP over IPv4 and IPv6 for a selected application while an
   unselected application continues to use normal domain/IP rules.
9. Test connected UDP, one-destination `sendto`, and one socket alternating at
   least two IPv4 and IPv6 destinations.
10. Test DNS UDP/TCP fallback, QUIC/HTTP3, Edge and one Electron application.
11. Test sleep/resume, network-interface switch, Core restart, upgrade,
    rollback and uninstall. No proxy, DNS, route, TUN, WFP or service residue may
    remain after uninstall or snapshot rollback.
12. If enterprise IPsec is supported, execute its separate compatibility matrix;
    otherwise confirm strict UDP remains unavailable for that configuration.

## Performance and resource bounds

13. Run 1, 128, 512 and 1,024 active flows with small, maximum-size, burst and
    sustained TCP/UDP traffic. Record throughput, loss, CPU, p50/p95/p99 latency,
    IOCTL rate, working set, locked memory and nonpaged-pool tags.
14. Run `Collect-M3VmEvidence.ps1` for at least 30 minutes during the fixed
    workload. Memory, handles, threads and pool use must stabilize after traffic
    and teardown; any monotonic growth is a failure pending investigation.
15. Prove overload remains bounded: no more than the documented receive,
    association, flow and in-flight injection limits, with selected traffic
    failing closed rather than consuming unbounded memory.

Return the completed checklist, preflight JSON, process samples, verifier output,
crash dumps and performance report. Do not return profiles, subscription URLs,
tokens, packet payloads, host/IP histories, user names or command lines.
