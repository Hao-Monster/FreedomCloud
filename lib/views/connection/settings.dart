import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const allConnectionTableColumns = [
  'status',
  'time',
  'type',
  'network',
  'host',
  'sniffHost',
  'source',
  'destination',
  'remoteDestination',
  'process',
  'processPath',
  'rule',
  'rulePayload',
  'chains',
  'uploadSpeed',
  'downloadSpeed',
  'upload',
  'download',
  'inbound',
  'uid',
  'id',
];

String connectionColumnLabel(String column) => switch (column) {
      'status' => appLocalizations.status,
      'time' => appLocalizations.connectionsEstablished,
      'type' => appLocalizations.connectionsType,
      'network' => appLocalizations.network,
      'host' => appLocalizations.connectionsHost,
      'sniffHost' => appLocalizations.connectionsSniffHost,
      'source' => appLocalizations.connectionsSource,
      'destination' => appLocalizations.connectionsDestination,
      'remoteDestination' => appLocalizations.connectionsRemoteDestination,
      'process' => appLocalizations.connectionsProcess,
      'processPath' => appLocalizations.connectionsProcessPath,
      'rule' => appLocalizations.connectionsRule,
      'rulePayload' => appLocalizations.connectionsRulePayload,
      'chains' => appLocalizations.connectionsProxyChain,
      'uploadSpeed' => appLocalizations.connectionsUploadSpeed,
      'downloadSpeed' => appLocalizations.connectionsDownloadSpeed,
      'upload' => appLocalizations.connectionsTotalUpload,
      'download' => appLocalizations.connectionsTotalDownload,
      'inbound' => appLocalizations.connectionsInbound,
      'uid' => appLocalizations.connectionsUid,
      'id' => 'ID',
      _ => column,
    };

void showConnectionSettings(BuildContext context) {
  unawaited(
    showExtend(
      context,
      props: const ExtendProps(maxWidth: 460),
      builder: (_, type) => AdaptiveSheetScaffold(
        type: type,
        title: appLocalizations.connectionsSettings,
        body: const ConnectionSettingsView(),
      ),
    ),
  );
}

class ConnectionSettingsView extends ConsumerStatefulWidget {
  const ConnectionSettingsView({super.key});

  @override
  ConsumerState<ConnectionSettingsView> createState() =>
      _ConnectionSettingsViewState();
}

class _ConnectionSettingsViewState
    extends ConsumerState<ConnectionSettingsView> {
  late final TextEditingController _intervalController;
  Timer? _debounce;
  String? _intervalError;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: '${ref.read(appSettingProvider).connectionRefreshInterval}',
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _intervalController.dispose();
    super.dispose();
  }

  void _update(AppSettingProps Function(AppSettingProps value) update) {
    ref.read(appSettingProvider.notifier).updateState(update);
  }

  void _onIntervalChanged(String text) {
    _debounce?.cancel();
    final value = int.tryParse(text);
    setState(() {
      _intervalError = value == null || value < 100 || value > 10000
          ? appLocalizations.connectionsRefreshIntervalDesc
          : null;
    });
    if (_intervalError != null) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _update(
          (settings) => settings.copyWith(connectionRefreshInterval: value!));
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SegmentedButton<ConnectionListMode>(
          segments: [
            ButtonSegment(
              value: ConnectionListMode.process,
              icon: const Icon(Icons.apps_rounded),
              label: Text(appLocalizations.connectionsProcessMode),
            ),
            ButtonSegment(
              value: ConnectionListMode.classic,
              icon: const Icon(Icons.view_list_rounded),
              label: Text(appLocalizations.connectionsClassicMode),
            ),
          ],
          selected: {settings.connectionListMode},
          onSelectionChanged: (values) => _update(
            (value) => value.copyWith(connectionListMode: values.first),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<ConnectionViewMode>(
          segments: [
            ButtonSegment(
              value: ConnectionViewMode.list,
              icon: const Icon(Icons.view_agenda_outlined),
              label: Text(appLocalizations.connectionsListView),
            ),
            ButtonSegment(
              value: ConnectionViewMode.table,
              icon: const Icon(Icons.table_rows_outlined),
              label: Text(appLocalizations.connectionsTableView),
            ),
          ],
          selected: {settings.connectionViewMode},
          onSelectionChanged: (values) => _update(
            (value) => value.copyWith(connectionViewMode: values.first),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(appLocalizations.connectionsShowIcons),
          value: settings.connectionShowIcon,
          onChanged: (value) => _update(
            (settings) => settings.copyWith(connectionShowIcon: value),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(appLocalizations.connectionsUseApplicationName),
          value: settings.connectionUseApplicationName,
          onChanged: (value) => _update(
            (settings) =>
                settings.copyWith(connectionUseApplicationName: value),
          ),
        ),
        const Divider(),
        TextField(
          controller: _intervalController,
          keyboardType: TextInputType.number,
          onChanged: _onIntervalChanged,
          decoration: InputDecoration(
            labelText: '${appLocalizations.connectionsRefreshInterval} (ms)',
            helperText: appLocalizations.connectionsRefreshIntervalDesc,
            errorText: _intervalError,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ConnectionSort>(
          initialValue: settings.connectionSort,
          decoration: InputDecoration(labelText: appLocalizations.sort),
          items: ConnectionSort.values
              .map(
                (sort) => DropdownMenuItem(
                  value: sort,
                  child: Text(_sortLabel(sort)),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) {
              _update((settings) => settings.copyWith(connectionSort: value));
            }
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<ConnectionSortDirection>(
          segments: [
            ButtonSegment(
              value: ConnectionSortDirection.ascending,
              icon: const Icon(Icons.arrow_upward_rounded),
              label: Text(appLocalizations.connectionsAscending),
            ),
            ButtonSegment(
              value: ConnectionSortDirection.descending,
              icon: const Icon(Icons.arrow_downward_rounded),
              label: Text(appLocalizations.connectionsDescending),
            ),
          ],
          selected: {settings.connectionSortDirection},
          onSelectionChanged: (values) => _update(
            (value) => value.copyWith(connectionSortDirection: values.first),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                appLocalizations.connectionsTableColumns,
                style: context.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => _update(
                (value) => value.copyWith(
                  connectionTableColumns: defaultConnectionTableColumns,
                  connectionTableColumnWidths: const {},
                ),
              ),
              child: Text(appLocalizations.connectionsResetColumns),
            ),
          ],
        ),
        for (final column in allConnectionTableColumns)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(connectionColumnLabel(column)),
            value: settings.connectionTableColumns.contains(column),
            onChanged: (selected) {
              final columns = List<String>.of(settings.connectionTableColumns);
              if (selected ?? false) {
                if (!columns.contains(column)) columns.add(column);
              } else if (columns.length > 1) {
                columns.remove(column);
              }
              _update(
                (value) => value.copyWith(connectionTableColumns: columns),
              );
            },
          ),
      ],
    );
  }

  String _sortLabel(ConnectionSort sort) => switch (sort) {
        ConnectionSort.time => appLocalizations.time,
        ConnectionSort.upload => appLocalizations.upload,
        ConnectionSort.download => appLocalizations.download,
        ConnectionSort.uploadSpeed => appLocalizations.connectionsUploadSpeed,
        ConnectionSort.downloadSpeed =>
          appLocalizations.connectionsDownloadSpeed,
        ConnectionSort.process => appLocalizations.connectionsProcess,
      };
}
