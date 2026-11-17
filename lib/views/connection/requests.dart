import 'dart:async';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/ui_activity.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'item.dart';

class RequestLogView extends ConsumerStatefulWidget {
  const RequestLogView({super.key});

  @override
  ConsumerState<RequestLogView> createState() => _RequestLogViewState();
}

class _RequestLogViewState extends ConsumerState<RequestLogView> {
  static const _consumerKey = 'requests_view';
  final _queryController = TextEditingController();
  String _query = '';
  bool _tickerEnabled = true;
  bool _subscribed = false;

  void _syncRequestsSubscription() {
    final shouldSubscribe = mounted && _tickerEnabled && uiActivity.value;
    if (shouldSubscribe == _subscribed) return;
    _subscribed = shouldSubscribe;
    final core = ClashCore.existingCore;
    if (core == null) return;
    if (shouldSubscribe) {
      unawaited(core.acquireRequestsConsumer(_consumerKey));
    } else {
      unawaited(core.releaseRequestsConsumer(_consumerKey));
    }
  }

  @override
  void initState() {
    super.initState();
    uiActivity.addListener(_syncRequestsSubscription);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncRequestsSubscription();
  }

  @override
  void dispose() {
    uiActivity.removeListener(_syncRequestsSubscription);
    if (_subscribed) {
      _subscribed = false;
      final core = ClashCore.existingCore;
      if (core != null) {
        unawaited(core.releaseRequestsConsumer(_consumerKey));
      }
    }
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(requestsProvider).list;
    final filtered = ConnectionsState(
      connections: requests,
      query: _query,
    ).list.reversed.toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _queryController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: appLocalizations.connectionsFilterHint,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _queryController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? NullStatus(
                  label: appLocalizations.nullTip(
                    appLocalizations.connectionsRequestLog,
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  itemBuilder: (_, index) => ConnectionRow(
                    key: ValueKey(filtered[index].id),
                    connection: filtered[index],
                  ),
                  separatorBuilder: (_, __) => const Divider(height: 0),
                ),
        ),
      ],
    );
  }
}
