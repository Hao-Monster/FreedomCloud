import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/clash/service.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/strict_policy.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/connection/item.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

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

/// Returns a stable, valid column order for settings loaded from disk.
///
/// Older builds did not validate this list, so a profile can contain unknown
/// or duplicate column ids. Keeping that data out of the table prevents
/// malformed layouts while preserving the user's configured order.
List<String> normalizeConnectionTableColumns(Iterable<String> columns) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final column in columns) {
    if (allConnectionTableColumns.contains(column) && seen.add(column)) {
      normalized.add(column);
    }
  }
  if (normalized.isEmpty) {
    normalized.addAll(defaultConnectionTableColumns);
  }
  return normalized;
}

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
    final selectedColumns =
        normalizeConnectionTableColumns(settings.connectionTableColumns);
    final hiddenColumns = allConnectionTableColumns
        .where((column) => !selectedColumns.contains(column))
        .toList(growable: false);
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
          onSelectionChanged: (values) {
            _update(
              (value) => value.copyWith(connectionListMode: values.first),
            );
            globalState.appController.updateClashConfigDebounce();
          },
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
        const _PerAppPolicySection(),
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
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: selectedColumns.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            final columns = List<String>.of(selectedColumns);
            final column = columns.removeAt(oldIndex);
            columns.insert(newIndex, column);
            _update(
              (value) => value.copyWith(connectionTableColumns: columns),
            );
          },
          itemBuilder: (_, index) {
            final column = selectedColumns[index];
            return CheckboxListTile(
              key: ValueKey(column),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(connectionColumnLabel(column)),
              value: true,
              onChanged: selectedColumns.length > 1
                  ? (selected) {
                      if (selected ?? true) return;
                      final columns = List<String>.of(selectedColumns)
                        ..remove(column);
                      _update(
                        (value) =>
                            value.copyWith(connectionTableColumns: columns),
                      );
                    }
                  : null,
              secondary: const Icon(Icons.drag_handle_rounded),
            );
          },
        ),
        for (final column in hiddenColumns)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(connectionColumnLabel(column)),
            value: false,
            onChanged: (selected) {
              if (selected ?? false) {
                _update(
                  (value) => value.copyWith(
                    connectionTableColumns: [
                      ...selectedColumns,
                      column,
                    ],
                  ),
                );
              }
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

class _PerAppPolicySection extends ConsumerStatefulWidget {
  const _PerAppPolicySection();

  @override
  State<_PerAppPolicySection> createState() => _PerAppPolicySectionState();
}

class _PerAppPolicySectionState extends ConsumerState<_PerAppPolicySection> {
  late final Future<void> _loaded = perAppPolicyStore.ensureLoaded();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<AgentStrictPolicyStatus>? _strictStatusSubscription;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _strictStatusSubscription = clashService?.strictPolicyStatusChanges.listen(
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    unawaited(_strictStatusSubscription?.cancel());
    _strictStatusSubscription = null;
    _searchController.dispose();
    super.dispose();
  }

  /// The strict capture control is available only on Windows Agent sessions.
  /// It is intentionally separate from whether a strict policy is currently
  /// armed: ordinary PROCESS-PATH edits must not unexpectedly activate the
  /// privileged data plane.
  bool get _strictAvailable =>
      Platform.isWindows && clashService?.usesAgent == true;

  bool get _strictCaptureActive =>
      _strictAvailable &&
      clashService?.strictPolicyStatus.state !=
          AgentStrictPolicyState.disabled;

  Future<bool> _prepareStrictEvidence(
    Iterable<PerAppPolicy> entries, {
    bool force = false,
  }) async {
    if (!_strictCaptureActive && !force) return true;
    final service = clashService;
    if (service == null) return false;
    final active = entries
        .where((entry) => entry.policy != ApplicationRoutingPolicy.inherit)
        .toList(growable: false);
    if (active.isEmpty) {
      return service.clearStrictPolicy();
    }
    final identities = <String, StrictIdentityResolution>{};
    for (final entry in active) {
      // Reinspect on every arm.  A path-only cache could reuse evidence after
      // an executable is replaced in place, which would violate the Broker's
      // locked-file identity guarantee.
      final identity = await service.inspectStrictIdentity(entry.path);
      if (identity == null || !strictIdentityMatchesPath(entry, identity)) {
        connectionDiagnostics.log(
          '[ConnectionsDiag] strict.identity status=unavailable '
          'reason=helperEvidence pathLength=${entry.path.length}',
        );
        return false;
      }
      identities[path.normalize(entry.path).toLowerCase()] = identity;
    }
    try {
      final policy = buildStrictPolicyBundle(
        entries: active,
        identities: identities,
        revision: DateTime.now().microsecondsSinceEpoch,
      );
      final applied = await service.applyStrictPolicy(policy);
      if (!applied) {
        connectionDiagnostics.log(
          '[ConnectionsDiag] strict.apply status=failed '
          'reason=agentRejected entries=${active.length}',
        );
      }
      return applied;
    } catch (error) {
      connectionDiagnostics.log(
        '[ConnectionsDiag] strict.apply status=invalid '
        'errorType=${error.runtimeType}',
      );
      return false;
    }
  }

  Future<void> _toggleStrictCapture() async {
    final service = clashService;
    if (service == null || !_strictAvailable) return;
    if (service.strictPolicyStatus.state != AgentStrictPolicyState.disabled) {
      final cleared = await service.clearStrictPolicy();
      if (mounted) {
        await context.showNotifier(
          cleared ? appLocalizations.successTitle : 'Strict mode is still active',
        );
      }
      return;
    }
    final armed = await _prepareStrictEvidence(
      perAppPolicyStore.entries,
      force: true,
    );
    if (mounted) {
      await context.showNotifier(
        armed ? appLocalizations.successTitle : 'Strict mode unavailable',
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _loaded,
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListenableBuilder(
            listenable: perAppPolicyStore,
            builder: (_, __) {
              final entries = perAppPolicyStore.entries;
              final filteredEntries =
                  filterPerAppPolicies(entries, _searchQuery);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${appLocalizations.connectionsProcessMode} · '
                              'PROCESS-PATH',
                              style: context.textTheme.titleMedium,
                            ),
                            Text(
                              '${entries.length} / $maxPerAppPolicies · '
                              'INHERIT / PROXY / DIRECT / BLOCK',
                              style: context.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: appLocalizations.add,
                        onPressed: _pickApplication,
                        icon: const Icon(Icons.add_rounded),
                      ),
                      if (_strictAvailable)
                        IconButton(
                          tooltip: 'Toggle strict application capture',
                          onPressed: _toggleStrictCapture,
                          icon: Icon(
                            clashService?.strictPolicyStatus.state ==
                                    AgentStrictPolicyState.armed
                                ? Icons.shield_rounded
                                : Icons.shield_outlined,
                          ),
                        ),
                    ],
                  ),
                  if (entries.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: appLocalizations.connectionsFilterHint,
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: appLocalizations.cancel,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                icon: const Icon(Icons.clear_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (filteredEntries.isEmpty && entries.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(appLocalizations.noData),
                      ),
                    ),
                  for (final entry in filteredEntries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ProcessIcon(
                        process: entry.name,
                        processPath: entry.path,
                        size: 36,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${entry.policy == ApplicationRoutingPolicy.proxy ? 'PROXY · ${entry.targetGroup ?? 'GLOBAL'}' : applicationRoutingPolicyLabel(entry.policy)} · '
                        '${entry.path}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _policyMenu(entry),
                          IconButton(
                            tooltip: appLocalizations.delete,
                            onPressed: () => _save(
                              entry.path,
                              entry.name,
                              ApplicationRoutingPolicy.inherit,
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          );
        },
      );

  PopupMenuButton<ApplicationRoutingPolicy> _policyMenu(
    PerAppPolicy entry,
  ) =>
      PopupMenuButton<ApplicationRoutingPolicy>(
        initialValue: entry.policy,
        tooltip: 'PROCESS-PATH',
        onSelected: (policy) => _save(entry.path, entry.name, policy),
        itemBuilder: (_) => ApplicationRoutingPolicy.values
            .map(
              (policy) => PopupMenuItem(
                value: policy,
                child: Text(applicationRoutingPolicyLabel(policy)),
              ),
            )
            .toList(growable: false),
      );

  Future<void> _pickApplication() async {
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isWindows ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isWindows ? const ['exe'] : null,
      allowMultiple: false,
      withData: false,
    );
    final processPath = result?.files.single.path;
    if (processPath == null || !mounted) return;
    final policy = await showDialog<ApplicationRoutingPolicy>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(path.basename(processPath)),
        children: ApplicationRoutingPolicy.values
            .where((value) => value != ApplicationRoutingPolicy.inherit)
            .map(
              (value) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, value),
                child: Text(applicationRoutingPolicyLabel(value)),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (policy == null) return;
    await _save(processPath, path.basename(processPath), policy);
  }

  Future<void> _save(
    String processPath,
    String name,
    ApplicationRoutingPolicy policy,
  ) async {
    try {
      final targetGroup = policy == ApplicationRoutingPolicy.proxy
          ? await showApplicationProxyGroupDialog(
              context,
              selectedGroup:
                  perAppPolicyStore.entryFor(processPath)?.targetGroup,
            )
          : null;
      if (policy == ApplicationRoutingPolicy.proxy && targetGroup == null) {
        return;
      }
      await perAppPolicyStore.setPolicy(
        processPath: processPath,
        name: name,
        policy: policy,
        targetGroup: targetGroup,
      );
      await globalState.appController.applyProfile();
      if (mounted) await context.showNotifier(appLocalizations.successTitle);
    } catch (error) {
      connectionDiagnostics.log(
        '[ConnectionsDiag] perApp.settings status=error '
        'errorType=${error.runtimeType}',
      );
      if (mounted) await context.showNotifier('ERROR: ${error.runtimeType}');
    }
  }
}
