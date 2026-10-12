# Local Windows resource fixes

This vendored package preserves the public `tray_manager` 0.5.2 Dart API and
the local Linux/macOS native sources. The input was the local Pub cache used by the existing
Windows previews, not an independently verified pristine upstream archive.
`LICENSE`, the upstream documentation, and platform build files are retained.

Input Windows source SHA256:
`24e19d45827a6d9ded599d1f3c3a7a1d0acc2ef095daf8ae784378a974be4460`.

## Menu ownership

The old `RemoveMenu` refresh detached submenus without destroying them. The
local implementation builds a complete replacement tree, owns every unappended
submenu, and transfers ownership to the parent only after `AppendMenuW`
succeeds. A successful replacement destroys the whole former root tree with
`DestroyMenu`; failed construction leaves the previous installed tree intact.
The root is also released on window/plugin destruction.

`TrackPopupMenu` runs a nested Windows message loop. While it is running, the
displayed tree remains alive. Successful background updates replace only the
pending tree, so at most the displayed tree and the latest pending tree remain
owned by the state. When tracking returns, the pending update is installed and
the former displayed tree is released. Nested popup requests are rejected.

Windows uses `TPM_RETURNCMD | TPM_NONOTIFY` and returns the selected item ID in
the internal popup response. The Dart wrapper captures the installed menu in
the same FIFO dispatch slot as the popup and resolves the ID against that local
snapshot. Background setters can still run while the popup is displayed. A
failed setter does not commit a new Dart action map; an old checkbox callback
cannot reinstall an old tree over an accepted or in-flight new setter. The
Windows Dart wrapper and native DLL must be shipped together. No unbounded
menu-generation map is kept.

Legacy native click events keep their original per-listener behavior, including
looking up the latest menu again for each listener and refreshing that latest
menu after a checkbox callback changes it. Windows popup response dispatch is
separate, so preserving the displayed snapshot does not alter Linux/macOS event
semantics. A regression test covers a checkbox callback that replaces its menu
while two listeners are installed.

The plugin and tracking stack share a menu lifetime. Window/plugin teardown
marks it disposed and requests deferred clearing. Tracking can return safely
after plugin destruction, reject late updates, release the displayed tree, and
skip replying to a destroyed Flutter engine without accessing plugin members.

The public `destroy()` method retains its original meaning of removing the
tray icon. It does not invalidate the menu during icon reset/re-add. The window
destruction path can request menu clearing; while tracking, clearing is deferred
until `TrackPopupMenu` returns.

## Icon and argument handling

Native icon structures start zeroed. Icon cleanup is idempotent and clears the
HICON field; a missing icon file reports failure and retains the old icon.
Shell registration failures also return an error. The registration helper
recovers both missing identities and already registered identities by trying
add/modify as appropriate, and only successful operations set the registration
flag. If registration fails, an existing old icon remains owned; on initial
failure the newly loaded icon is retained as the one retry resource. Taskbar
recreation/resume retries use an owned HICON rather than the success flag;
public destroy clears that HICON and cannot inadvertently restore a deleted
icon. The actual Shell failure/recovery paths are not injected on the user's
desktop; seven deterministic operation sequences and native compilation cover
the helper and integration syntax.
Menu map fields and UTF-8 labels are validated without depending on C++ STL
exceptions, matching Flutter's `_HAS_EXCEPTIONS=0` build. Menu allocation or
append failures return a platform error and release all partial new resources.

## Verification

See `WINDOWS-RESOURCE-TESTS.md`, `windows/tests/Run-Tests.ps1`, and the root
`test/common/tray_plugin_menu_test.dart`. Tests are standalone C++ executables
or Flutter platform-channel tests; they never launch FlClashX or alter networking.
Native Win32 probes use a private desktop without displaying or switching it.
Only test binaries/objects in ignored `windows/tests/build/` are generated.

The menu-only Win32 tests prove resource ownership and replacement. Actual
mouse-driven popup interactions and long-running full-client acceptance remain
separate verification steps. Linux/macOS native sources are unchanged and are not
built by these Windows tests.
