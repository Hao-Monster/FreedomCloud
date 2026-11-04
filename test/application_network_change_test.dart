import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flclashx/application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows adapter notifications keep existing Core connections', () {
    for (final results in [
      [ConnectivityResult.ethernet],
      [ConnectivityResult.ethernet, ConnectivityResult.vpn],
      [ConnectivityResult.none],
      [ConnectivityResult.wifi],
    ]) {
      expect(
        shouldCloseConnectionsOnNetworkChange(results, isWindows: true),
        isFalse,
      );
    }
  });

  test('other platforms retain the existing VPN guard', () {
    expect(
      shouldCloseConnectionsOnNetworkChange(
        [ConnectivityResult.wifi],
        isWindows: false,
      ),
      isTrue,
    );
    expect(
      shouldCloseConnectionsOnNetworkChange(
        [ConnectivityResult.wifi, ConnectivityResult.vpn],
        isWindows: false,
      ),
      isFalse,
    );
  });
}
