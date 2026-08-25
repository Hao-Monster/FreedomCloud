# Windows 11 VM acceptance checklist

1. Snapshot the clean VM and extract the ZIP to a fixed folder.
2. Start `FlClashX.exe`. Approve the one-time Helper registration only when
   enabling the virtual network card; record the exact UAC command if it repeats.
3. Restart FlClashX twice. A healthy existing service must not be deleted or
   cause another repair prompt.
4. Run `sc qc FlClashHelperService` and confirm `BINARY_PATH_NAME` is
   `C:\Program Files\FlClashX Service\FlClashHelperService.exe`.
5. Enable the virtual network card in the VM, open Edge and browse
   `google.com`. Verify the real Edge network process appears with icon, totals
   and rates. Repeat with one Electron application if available.
6. Exercise process/classic, list/table, search by process/host/IP/proxy/rule,
   every sort/direction, pause/resume, details, close-one, close-filtered,
   closed history and clear history.
7. Set one application to a policy group, DIRECT and REJECT in turn. Verify an
   unselected application continues to use ordinary domain/IP rules.
8. Open Zashboard and exercise connections/proxies while the native page is
   refreshing, paused and closing rows.
9. Hide the window for five minutes. Record CPU and memory, then reopen and
   confirm one immediate refresh without stale rates.
10. Export `connections_diagnostic.log`. Check it contains no username, process
    path, host, IP, subscription URL, secret or authorization header.
11. Zip the diagnostic file plus screenshots and return them with PASS/FAIL for
    each step. Do not include subscription/profile files.
