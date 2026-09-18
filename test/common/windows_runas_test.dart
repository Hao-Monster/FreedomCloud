import 'package:flclashx/common/windows.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
