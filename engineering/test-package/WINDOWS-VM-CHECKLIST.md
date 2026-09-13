# Windows 11 VM acceptance checklist

Test artifact: `FlClashX-windows-amd64.zip` (unsigned portable local acceptance
build). If a matching `FlClashX-windows-amd64-setup.exe` is present, verify its
adjacent `.sha256` file before using it. Do not use either artifact as a
production release.

Record PASS/FAIL and evidence for every numbered step. Take a VM snapshot before
installation and do not copy subscription/profile files into the return bundle.

## A. Install, privilege and process ownership

1. Verify the ZIP SHA-256 against the adjacent `.sha256` file, extract it in the
   clean Windows 11 VM, and verify extracted files against `SHA256SUMS.txt`.
   If testing an installer, verify its own adjacent `.sha256` file first.
2. Start FlClashX normally. Do not run the UI as Administrator. Approve the
   one-time Helper registration only when the virtual network card requires it;
   capture the exact UAC command if a prompt appears.
3. Exit and start FlClashX twice. A healthy existing service must not be deleted,
   recreated or produce another repair UAC prompt.
4. Run `sc qc FlClashHelperService` and confirm `BINARY_PATH_NAME` is
   `C:\Program Files\FlClashX Service\FlClashHelperService.exe`.
5. With the UI open, record PID and memory for `FlClashX.exe`,
   `FlClashAgent.exe`, `FlClashCore.exe` and `FlClashHelperService.exe`.

## B. Agent lifecycle (R-120 through R-124)

6. Enable the existing virtual network card and establish continuous traffic in
   the VM. Close only the UI window. Confirm `FlClashX.exe` exits while Agent and
   Core remain, traffic continues, and no hidden Flutter process remains.
7. Reopen FlClashX. Confirm it attaches without a new Agent PID, active traffic
   remains usable, the profile/listener is not visibly restarted and no UAC
   prompt occurs.
8. Use UI restart. Confirm UI PID changes but Agent PID remains and continuous
   traffic is not interrupted.
9. Use **Stop proxy**. Confirm Agent remains available while proxy/TUN state is
   stopped. Start it again and confirm normal recovery.
10. Use **Full exit**. Confirm UI, Agent and Core exit, system proxy/DNS cleanup
    completes and the Agent endpoint file is removed. Helper may remain installed
    but must be idle.
11. Start again after full exit. Confirm exactly one Agent is created. Quickly
    open a second UI instance if possible; only the newest authenticated UI may
    control Agent and neither UI may crash Core.

## C. Connections, application policy and Zashboard

12. Open Edge and browse `google.com`. Verify the real Edge network process
    appears with icon, totals and rates. Repeat with one Electron application if
    available. If empty, export diagnostics before changing any settings.
13. Exercise process/classic, list/table, search by process/host/IP/proxy/rule,
    every sort/direction, pause/resume, details, close-one, close-filtered,
    closed history and clear history.
14. Set one application to a policy group, DIRECT and REJECT in turn. Verify an
    unselected application continues to use ordinary domain/IP rules.
15. Open Zashboard and exercise connections/proxies while the native page is
    refreshing, paused and closing rows. Active/Log and Zashboard must remain
    functional and must not be reset by changing native display modes.

## D. Performance, diagnostics, upgrade and rollback

16. Close the UI for five minutes while traffic continues. Record Agent/Core
    CPU and private working set at 0, 1 and 5 minutes. Reopen and record Flutter
    memory separately. There must be no monotonic Agent growth attributable to
    connection/icon snapshots.
17. Run `Collect-FlClashXLogs.ps1 -OutputDirectory <evidence-directory>` after
    the Edge test. It copies the bounded Flutter, Agent, Helper and Strict
    Broker logs plus recent Service Control Manager events. Check that the
    privacy-safe `connections_diagnostic.log` contains no username, process
    path, host, IP, subscription URL, secret or authorization header.
18. Run the same installer over the installed build. Confirm upgrade can stop
    Agent/Core cleanly and restart without duplicate Agent/Helper processes.
19. Uninstall. Confirm FlClashX, Agent and Core are gone, service cleanup is
    correct, no system proxy/DNS/TUN state is left active and ordinary networking
    still works.
20. If any lifecycle/network step fails, collect screenshots, Task Manager
    process details, the evidence directory, installer version/hash and the
    step number. Restore the VM snapshot after collection.

Return one ZIP containing the completed checklist, screenshots and redacted
logs. Do not include profile YAML, subscriptions, credentials or the per-user
Agent/Helper token files.
