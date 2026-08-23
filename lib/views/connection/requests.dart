import 'package:flclashx/common/common.dart';
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
  final _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
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
