import 'dart:async';
import 'dart:io';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/models/common.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';

final _memoryInfoStateNotifier = ValueNotifier<TrafficValue>(
  const TrafficValue(value: 0),
);

class MemoryInfo extends StatefulWidget {
  const MemoryInfo({super.key});

  @override
  State<MemoryInfo> createState() => _MemoryInfoState();
}

class _MemoryInfoState extends State<MemoryInfo> {
  Timer? timer;
  bool _tickerEnabled = true;
  bool _pollingInFlight = false;

  bool get _shouldPoll => mounted && _tickerEnabled && uiActivity.value;

  @override
  void initState() {
    super.initState();
    uiActivity.addListener(_syncPollingState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncPollingState();
  }

  void _syncPollingState() {
    if (_shouldPoll) {
      if (timer == null && !_pollingInFlight) {
        _scheduleImmediateUpdate();
      }
    } else {
      timer?.cancel();
      timer = null;
    }
  }

  @override
  void dispose() {
    uiActivity.removeListener(_syncPollingState);
    timer?.cancel();
    timer = null;
    super.dispose();
  }

  void _scheduleImmediateUpdate() {
    if (_pollingInFlight || !_shouldPoll) return;
    _pollingInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!_shouldPoll) return;
        final rss = ProcessInfo.currentRss;
        final total = clashLib != null ? rss : await clashCore.getMemory() + rss;
        if (!mounted) return;
        _memoryInfoStateNotifier.value = TrafficValue(value: total);
      } finally {
        _pollingInFlight = false;
      }
      if (_shouldPoll && timer == null) {
        timer = Timer(const Duration(seconds: 2), () {
          timer = null;
          _scheduleImmediateUpdate();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: getWidgetHeight(1),
        child: CommonCard(
          info: Info(
            iconData: Icons.memory,
            label: appLocalizations.memoryInfo,
          ),
          onPressed: clashCore.requestGc,
          child: Container(
            padding: baseInfoEdgeInsets.copyWith(
              top: 0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: globalState.measure.bodyMediumHeight + 2,
                  child: ValueListenableBuilder(
                    valueListenable: _memoryInfoStateNotifier,
                    builder: (_, trafficValue, __) => Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          trafficValue.showValue,
                          style: context.textTheme.bodyMedium?.toLight
                              .adjustSize(1),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Text(
                          trafficValue.showUnit,
                          style: context.textTheme.bodyMedium?.toLight
                              .adjustSize(1),
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      );
}
