import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flclashx/common/windows.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingAllocator implements Allocator {
  final Set<int> liveAddresses = <int>{};
  int allocateCalls = 0;
  int freeCalls = 0;

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    allocateCalls++;
    final ptr = calloc.allocate<T>(byteCount, alignment: alignment);
    liveAddresses.add(ptr.address);
    return ptr;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    freeCalls++;
    final removed = liveAddresses.remove(pointer.address);
    if (!removed) {
      throw StateError('Double or unknown free for address ${pointer.address}');
    }
    calloc.free(pointer);
  }
}

void main() {
  test('ShellExecute treats documented failures as failures', () {
    expect(windowsShellExecuteSucceeded(0), isFalse);
    expect(windowsShellExecuteSucceeded(5), isFalse);
    expect(windowsShellExecuteSucceeded(32), isFalse);
  });

  test('ShellExecute accepts every documented success result', () {
    expect(windowsShellExecuteSucceeded(33), isTrue);
    expect(windowsShellExecuteSucceeded(42), isTrue);
    expect(windowsShellExecuteSucceeded(255), isTrue);
  });

  test('runWindowsShellExecute marshals UTF-16 strings and frees native buffers on success', () {
    final tracker = _TrackingAllocator();
    String? capturedOp;
    String? capturedFile;
    String? capturedParams;

    final ok = runWindowsShellExecute(
      command: 'cmd.exe',
      arguments: '/d /v:on /s /c "echo ok"',
      allocator: tracker,
      resolveShellExecute: () => (
        hwnd,
        lpOperation,
        lpFile,
        lpParameters,
        lpDirectory,
        nShowCmd,
      ) {
        capturedOp = lpOperation.toDartString();
        capturedFile = lpFile.toDartString();
        capturedParams = lpParameters.toDartString();
        expect(hwnd, nullptr);
        expect(lpDirectory, nullptr);
        expect(nShowCmd, 0);
        return 42;
      },
    );

    expect(ok, isTrue);
    expect(capturedOp, 'runas');
    expect(capturedFile, 'cmd.exe');
    expect(capturedParams, '/d /v:on /s /c "echo ok"');
    expect(tracker.allocateCalls, 3);
    expect(tracker.freeCalls, 3);
    expect(tracker.liveAddresses, isEmpty);
  });

  test('runWindowsShellExecute frees native buffers even when symbol lookup or invocation throws', () {
    final lookupTracker = _TrackingAllocator();
    expect(
      () => runWindowsShellExecute(
        command: 'cmd.exe',
        arguments: '/c ver',
        allocator: lookupTracker,
        resolveShellExecute: () =>
            throw ArgumentError('Failed to lookup ShellExecuteW'),
      ),
      throwsArgumentError,
    );
    expect(lookupTracker.liveAddresses, isEmpty);
    expect(lookupTracker.allocateCalls, lookupTracker.freeCalls);

    final invokeTracker = _TrackingAllocator();
    expect(
      () => runWindowsShellExecute(
        command: 'cmd.exe',
        arguments: '/c ver',
        allocator: invokeTracker,
        resolveShellExecute: () => (_, __, ___, ____, _____, ______) {
          throw StateError('FFI invocation aborted');
        },
      ),
      throwsStateError,
    );
    expect(invokeTracker.allocateCalls, 3);
    expect(invokeTracker.freeCalls, 3);
    expect(invokeTracker.liveAddresses, isEmpty);
  });
}
