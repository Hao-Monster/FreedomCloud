# Windows menu resource regression plan

Frozen before the resource fix on 2026-10-08. The starting implementation is
the local `tray_manager` 0.5.2 source; its Windows source SHA256 was
`24e19d45827a6d9ded599d1f3c3a7a1d0acc2ef095daf8ae784378a974be4460`.
The package's Dart API and Linux/macOS implementations must remain compatible.

| ID | Requirement / risk | Executable verification | Expected result |
| --- | --- | --- | --- |
| M01 | Old `RemoveMenu` path loses submenu ownership | Small standalone C++ Win32 probe on a private, undisplayed desktop; alternatively a deterministic Win32 ownership substitute | Detached old submenu remains valid after removing it and destroying its former parent; explicitly destroying it releases the resource |
| M02 | Repeated refresh of a multi-level menu | Production menu builder/state with deterministic menu API, 200 refreshes | Only the current menu tree remains live; state destruction frees every menu |
| M03 | Root lifecycle | Construct, replace, clear, destroy production state | Every root is destroyed exactly once; no leaked menus |
| M04 | Background refresh while `TrackPopupMenu` is active | Begin tracking, submit two menu trees, end tracking | Active tree remains valid while tracking; only latest pending tree is installed; superseded pending tree is destroyed |
| M05 | Window termination clear while tracking | Begin tracking, clear state, end tracking | Active tree survives until tracking ends, then is destroyed; no pending tree leaks; public icon-only `destroy()` preserves the menu |
| M06 | Root or recursive `CreatePopupMenu` fails | Inject failure at each allocation site in production builder | Build reports failure; previous installed menu remains intact; incomplete tree is fully destroyed |
| M07 | `AppendMenuW` fails, including after building a child tree | Inject failure at each append site in production builder | Build reports failure; unattached child and attached ancestors are fully destroyed |
| M08 | Failed replacement during tracking | Fail a new build while an earlier pending update exists | Active and latest successful pending tree remain intact |
| M09 | Reentrant popup request | Begin tracking twice | Second request is rejected; tracking state and active menu remain valid |
| M10 | Native integration | Compile the vendored Windows Flutter plugin with the project's toolchain | No C++ compile/link failures; native binary rebuilt from vendored source |

The Win32 probe is bounded to a few hundred operations, does not switch the
visible desktop, and never starts FlClashX or changes proxy/TUN/services.
If desktop exhaustion prevents real Win32 allocations, record that limitation;
deterministic ownership tests must use the actual production builder/state.

Results and exact commands are recorded below after execution.

## Executed results (2026-10-08)

Environment: Windows x64, MSVC 14.44.35207, Windows SDK 10.0.26100.0.
Compiler gates: C++17, `/W4 /WX /EHsc /D_HAS_EXCEPTIONS=0`.
Native Flutter compilation additionally uses the project's `/wd4100`, Unicode,
plugin-export, and codecvt deprecation definitions.

Commands run from the repository root:

| Command | Result | Process exit | Elapsed (compile + run) | Evidence |
| --- | --- | --- | --- | --- |
| `& ./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode LegacyProbe` | Expected failing old cleanup assertion: root removal succeeds, but child and grandchild remain valid | 2 (PowerShell command wrapper reports 1) | 1227 ms | `windows/tests/build/LegacyProbe.log` |
| `& ./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode Regression` | PASS, 6 test groups, 0 failed, 0 skipped; includes every 3 create / 7 append failure site | 0 | 945 ms | `windows/tests/build/Regression.log` |
| `& ./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode Win32` | PASS, 200 real Win32 multi-level refreshes; prior root/child/grandchild invalid after replacement; USER baseline 1, final 1 | 0 | 1294 ms | `windows/tests/build/Win32.log` |
| `& ./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode NativeCompile` | PASS, production Flutter plugin C++ compilation with warnings as errors | 0 | 1645 ms | `windows/tests/build/NativeCompile.log`; object `windows/tests/build/NativeCompile.obj` |

The old cleanup probe and fixed implementation tests use separate executables.
This is a direct old-pattern failure / fixed-production-builder pass comparison,
not a claim that one full-client integration test was run on both binaries.
The old probe explicitly destroys the demonstrated orphan menus before exiting.
Win32 tests create and close a private desktop without displaying it.

Coverage percentages are not collected by these standalone native tests. The
menu builder's resource failure sites and tracking transitions are enumerated
explicitly. Full-client mouse interactions, Explorer recovery on the current
desktop, and Linux/macOS builds: NOT RUN here. The main task owns the full
native DLL link and preview-package verification.

## Additional boundary matrix (frozen before the follow-up fix)

| ID | Boundary risk | Verification | Expected result |
| --- | --- | --- | --- |
| B01 | Background updates replace Dart mapping while the old native popup remains displayed | `tray_plugin_menu_test.dart`: displayed A, submit B/C, return selected A id | A action dispatches exactly once |
| B02 | Native replacement fails but Dart mapping points at the failed menu | Failed setter then popup selecting last installed A | Failed setter reports error; A action still works |
| B03 | Popup races with in-flight/native queued setters | Hold first setter, enqueue popup then next setter | FIFO native dispatch: setter, popup, setter; snapshot matches popup |
| B04 | Reentrant or failed popup leaves a stuck guard | Second popup during tracking, cancellation, native failure and retry | Reentrant popup fails; future popup succeeds |
| B05 | Old checkbox mutates after a new menu was accepted | Display A, replace B, select checkbox A | A action runs without reinstalling stale A over B |
| B06 | Non-Windows callback behavior | Legacy `onTrayMenuItemClick` event on Linux target | Existing event callback delivery is preserved |
| B07 | Plugin owner destroyed inside native tracking loop | Production shared lifetime, dispose/reset owner during tracking | Current native tree survives until tracking ends; late updates rejected; stack state is safe |
| B08 | Shell tray icon registration fails | Seven deterministic registration operation sequences, production C++ compilation and independent branch review | Failed registration reports an error, retains one HICON retry resource, and does not claim a successful add |
| B09 | Shared callback code changes legacy per-listener menu replacement semantics | Linux checkbox callback replaces its menu with two listeners installed | Automatic refresh uses latest menu; second listener does not repeat an old menu callback |

The boundary tests use platform-channel results as the external boundary;
the real resource tests still validate production menu ownership with Win32.

## Follow-up results

| Command | Result | Exit | Evidence |
| --- | --- | --- | --- |
| `& E:/flutter/bin/flutter.bat test test/common/tray_plugin_menu_test.dart --reporter expanded` before the boundary fix | RED: 2 passed, 5 failed for lost old-menu actions, setter ordering, popup guard, and checkbox callback | 1 | `windows/tests/build/PluginBoundary-Red.log` |
| `& E:/flutter/bin/flutter.bat test test/common/tray_plugin_menu_test.dart test/common/tray_refresh_test.dart --reporter expanded` after the fix | GREEN: 17 passed, 0 failed, 0 skipped; 9 plugin boundary tests plus 8 app refresh tests | 0 | `windows/tests/build/PluginBoundary-Green.log` |
| `& E:/flutter/bin/flutter.bat test test/common/tray_plugin_menu_test.dart --plain-name 'legacy checkbox callback refreshes the latest replaced menu per listener' --reporter expanded` before the compatibility correction | RED: 1 failed because the old menu was reinstalled and a second listener repeated the old action | 1 | `windows/tests/build/LegacyCallback-Red.log` |
| `& E:/flutter/bin/flutter.bat test test/common/tray_plugin_menu_test.dart --reporter expanded` on the final frozen source | GREEN: all 10 plugin boundary tests passed, 0 failed, 0 skipped | 0 | `windows/tests/build/PluginBoundary-Final-Green.log` |
| `& E:/flutter/bin/flutter.bat analyze test/common/tray_plugin_menu_test.dart --no-pub --no-fatal-infos` | PASS: no issues found; 4.2 seconds reported | 0 | `windows/tests/build/PluginBoundary-Analyze.log` |
| `& ./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode Regression` | PASS: 8 native test groups, including owner disposal/reset during tracking and 7 icon add/modify/failure/recovery operation sequences; 979 ms | 0 | `windows/tests/build/Regression.log` |
| `& ./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode Win32` | PASS: 200 refreshes plus owner destruction during tracking/late-update rejection; USER baseline 1, final 1; 1351 ms | 0 | `windows/tests/build/Win32.log` |
| `& ./plugins/tray_manager/windows/tests/Run-Tests.ps1 -Mode NativeCompile` after the final native recovery guards | PASS: production plugin compiles under the project warning/exception gates; 1334 ms | 0 | `windows/tests/build/NativeCompile.log` |

Native owner-destruction tests exercise the actual shared-lifetime state with
real Win32 menu handles. Destroying a real Flutter engine inside an actual popup
is NOT RUN; the plugin's no-member-access/no-reply disposal branch is checked by
source review and native compilation. Actual Shell failure injection, Explorer
restart/resume recovery with the full client, and physical mouse popup operation
are NOT RUN. Icon helper tests do not claim to prove a live Shell recovery.

Independent final source review found no remaining medium/high issue in the
menu lifetime, Windows FIFO/action snapshot, legacy event compatibility, or
icon registration recovery changes. Full-client acceptance limitations above
remain. Formatter output retains the upstream package's unresolved
`mostly_reasonable_lints` development-only include in the root dependency
context; formatting succeeded and the new root test analyzer reports no issues.
