import 'package:flclashx/common/delay_test_coordinator.dart';
import 'package:flutter/material.dart';

class DelayTestAction extends StatelessWidget {
  const DelayTestAction(
      {super.key,
      required this.coordinator,
      required this.onStart,
      required this.startLabel,
      required this.cancelLabel});

  final DelayTestCoordinator coordinator;
  final Future<void> Function() onStart;
  final String startLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: coordinator,
        builder: (_, __) => IconButton(
          tooltip: coordinator.busy ? cancelLabel : startLabel,
          onPressed: coordinator.busy ? coordinator.cancel : onStart,
          icon: Icon(
              coordinator.busy ? Icons.cancel_outlined : Icons.network_ping),
        ),
      );
}
