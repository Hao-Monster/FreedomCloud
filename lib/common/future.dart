import 'dart:async';
import 'dart:ui';

extension CompleterExt<T> on Completer<T> {
  Future<T> safeFuture({
    Duration? timeout,
    VoidCallback? onLast,
    FutureOr<T> Function()? onTimeout,
    required String functionName,
  }) {
    final realTimeout = timeout ?? const Duration(seconds: 30);
    return future.withTimeout(
      timeout: realTimeout,
      functionName: functionName,
      onTimeout: onTimeout,
    ).whenComplete(() => onLast?.call());
  }
}

extension FutureExt<T> on Future<T> {
  Future<T> withTimeout({
    required Duration timeout,
    required String functionName,
    FutureOr<T> Function()? onTimeout,
  }) => this.timeout(
      timeout,
      onTimeout: () async {
        if (onTimeout != null) {
          return onTimeout();
        } else {
          throw TimeoutException('$functionName timeout');
        }
      },
    );
}
