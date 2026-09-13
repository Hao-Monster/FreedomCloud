import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/manager/connection_manager.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/zashboard.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'detail.dart';
import 'item.dart';
import 'requests.dart';
import 'settings.dart';
import 'table.dart';

enum _ConnectionStatusTab { active, closed }

class ConnectionsView extends ConsumerStatefulWidget {
  const ConnectionsView({super.key});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView>
    with PageMixin {
  final _queryController = TextEditingController();
  String _query = '';
  String? _selectedProcessKey;
  _ConnectionStatusTab _status = _ConnectionStatusTab.active;
  bool _isCurrentPage = false;

  @override
  List<Widget> get actions => [
        IconButton(
          tooltip: appLocalizations.exportLogs,
          onPressed: () => unawaited(_exportDiagnostics()),
          icon: const Icon(Icons.download_outlined),
        ),
        IconButton(
          tooltip: appLocalizations.connectionsRequestLog,
          onPressed: _showRequestLog,
          icon: const Icon(Icons.receipt_long_outlined),
        ),
        const _PauseButton(),
        IconButton(
          tooltip: appLocalizations.connectionsSettings,
          onPressed: () => showConnectionSettings(context),
          icon: const Icon(Icons.tune_rounded),
        ),
        const _ZashboardButton(),
      ];

  Future<void> _exportDiagnostics() async {
    final bytes = await connectionDiagnostics.exportBytes();
    final path = await picker.saveFile(
      ConnectionDiagnostics.fileName,
      bytes,
    );
    if (path != null && mounted) {
      await context.showNotifier(appLocalizations.exportSuccess);
    }
  }

  @override
  void initState() {
    super.initState();
    window?.visible.addListener(_syncManagerVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      connectionDiagnostics.log(
        '[ConnectionsDiag] page.open '
        'runtime=${ref.read(runTimeProvider) != null} '
        'managerRunning=${connectionManager.running} '
        'loading=${connectionManager.loading} '
        'active=${connectionManager.activeConnections.length} '
        'groups=${connectionManager.processGroups.length}',
      );
    });
    ref.listenManual(
      isCurrentPageProvider(
        PageLabel.connections,
        handler: (pageLabel, viewMode) =>
            pageLabel == PageLabel.tools && viewMode == ViewMode.mobile,
      ),
      (_, current) {
        _isCurrentPage = current;
        _syncManagerVisibility();
        if (current) initPageState();
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    window?.visible.removeListener(_syncManagerVisibility);
    _isCurrentPage = false;
    _syncManagerVisibility();
    connectionDiagnostics.log(
      '[ConnectionsDiag] page.close '
      'managerRunning=${connectionManager.running} '
      'active=${connectionManager.activeConnections.length} '
      'groups=${connectionManager.processGroups.length}',
    );
    _queryController.dispose();
    super.dispose();
  }

  void _syncManagerVisibility() {
    connectionManager.setViewVisible(
      visible: _isCurrentPage && (window?.visible.value ?? true),
    );
  }

  void _showRequestLog() {
    unawaited(
      showExtend(
        context,
        props: const ExtendProps(maxWidth: 520),
        builder: (_, type) => AdaptiveSheetScaffold(
          type: type,
          title: appLocalizations.connectionsRequestLog,
          body: const RequestLogView(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingProvider);
    return ListenableBuilder(
      listenable: connectionManager,
      builder: (_, __) {
        final groups = sortProcessConnectionGroups(
          _filteredGroups(connectionManager.processGroups, _query),
          settings.connectionSort,
          direction: settings.connectionSortDirection,
        );
        final selectedGroup = _selectedProcessKey == null
            ? null
            : connectionManager.processGroups
                .where((group) => group.key == _selectedProcessKey)
                .firstOrNull;
        final showProcessOverview =
            settings.connectionListMode == ConnectionListMode.process &&
                selectedGroup == null;
        final source = showProcessOverview
            ? const <TrackedConnection>[]
            : _connectionsFor(selectedGroup);
        final filtered = sortTrackedConnections(
          filterTrackedConnections(source, _query),
          settings.connectionSort,
          direction: settings.connectionSortDirection,
        );
        final closeable = showProcessOverview
            ? filterTrackedConnections(
                connectionManager.activeConnections,
                _query,
              )
            : _status == _ConnectionStatusTab.active
                ? filtered
                : const <TrackedConnection>[];
        return Column(
          children: [
            _SummaryHeader(
              activeCount: connectionManager.activeConnections.length,
              closedCount: connectionManager.closedConnections.length,
              upload: connectionManager.uploadTotal,
              download: connectionManager.downloadTotal,
              uploadSpeed: connectionManager.activeUploadSpeed,
              downloadSpeed: connectionManager.activeDownloadSpeed,
            ),
            if (connectionManager.paused)
              MaterialBanner(
                content: Text(appLocalizations.connectionsPaused),
                actions: [
                  TextButton(
                    onPressed: () => connectionManager.setPaused(paused: false),
                    child: Text(appLocalizations.connectionsResume),
                  ),
                ],
              ),
            if (connectionManager.error != null)
              MaterialBanner(
                content: Text('${connectionManager.error}'),
                actions: [
                  TextButton(
                    onPressed: () => unawaited(connectionManager.refresh()),
                    child: Text(appLocalizations.update),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  SegmentedButton<ConnectionListMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ConnectionListMode.process,
                        label: Text(appLocalizations.connectionsProcessMode),
                      ),
                      ButtonSegment(
                        value: ConnectionListMode.classic,
                        label: Text(appLocalizations.connectionsClassicMode),
                      ),
                    ],
                    selected: {settings.connectionListMode},
                    onSelectionChanged: (values) {
                      setState(() => _selectedProcessKey = null);
                      ref.read(appSettingProvider.notifier).updateState(
                            (value) => value.copyWith(
                              connectionListMode: values.first,
                            ),
                          );
                      globalState.appController.updateClashConfigDebounce();
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _searchField()),
                  if (closeable.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: appLocalizations.connectionsCloseFiltered,
                      onPressed: () => unawaited(
                        connectionManager.closeConnections(
                          closeable.map((item) => item.connection.id),
                        ),
                      ),
                      icon: const Icon(Icons.link_off_rounded),
                    ),
                  ],
                  if (!showProcessOverview) ...[
                    if (_status == _ConnectionStatusTab.closed &&
                        connectionManager.closedConnections.isNotEmpty)
                      IconButton(
                        tooltip: appLocalizations.connectionsClearClosed,
                        onPressed: connectionManager.clearClosed,
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                  ],
                ],
              ),
            ),
            if (!showProcessOverview) _statusBar(selectedGroup),
            if (selectedGroup != null)
              _processBreadcrumb(selectedGroup, settings),
            Expanded(
              child: connectionManager.loading
                  ? const Center(child: CircularProgressIndicator())
                  : showProcessOverview
                      ? _processList(groups, settings)
                      : _connectionList(filtered, settings),
            ),
          ],
        );
      },
    );
  }

  Widget _searchField() => TextField(
        controller: _queryController,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          isDense: true,
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
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _statusBar(ProcessConnectionGroup? selectedGroup) {
    final activeCount = selectedGroup?.activeCount ??
        connectionManager.activeConnections.length;
    final closedCount = selectedGroup?.closedCount ??
        connectionManager.closedConnections.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: CommonTabBar<_ConnectionStatusTab>(
        groupValue: _status,
        thumbColor: context.colorScheme.surface,
        backgroundColor: context.colorScheme.surfaceContainerHighest,
        onValueChanged: (value) {
          if (value != null) setState(() => _status = value);
        },
        children: {
          _ConnectionStatusTab.active: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Text('${appLocalizations.connectionsActive}  $activeCount'),
          ),
          _ConnectionStatusTab.closed: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Text('${appLocalizations.connectionsClosed}  $closedCount'),
          ),
        },
      ),
    );
  }

  Widget _processBreadcrumb(
    ProcessConnectionGroup group,
    AppSettingProps settings,
  ) {
    final first = group.activeConnections.firstOrNull?.connection ??
        group.closedConnections.first.connection;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: appLocalizations.connectionsAllProcesses,
            onPressed: () => setState(() => _selectedProcessKey = null),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          ProcessIcon(
            process: group.name,
            processPath: group.processPath,
            connectionType: first.metadata.type,
            enabled: settings.connectionShowIcon,
            size: 32,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              connectionProcessName(
                first.metadata,
                applicationName: settings.connectionUseApplicationName,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _processList(
    List<ProcessConnectionGroup> groups,
    AppSettingProps settings,
  ) {
    if (groups.isEmpty) {
      return NullStatus(
        label: appLocalizations.nullTip(appLocalizations.connectionsProcess),
      );
    }
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (_, index) {
        final group = groups[index];
        return ProcessConnectionCard(
          key: ValueKey(group.key),
          group: group,
          showIcon: settings.connectionShowIcon,
          useApplicationName: settings.connectionUseApplicationName,
          policy: perAppPolicyStore.policyFor(group.processPath),
          onPolicyChanged: group.processPath.isEmpty
              ? null
              : (policy) => unawaited(
                    _setApplicationPolicy(group, policy),
                  ),
          onTap: () => setState(() {
            _selectedProcessKey = group.key;
            _status = group.activeCount > 0
                ? _ConnectionStatusTab.active
                : _ConnectionStatusTab.closed;
          }),
        );
      },
    );
  }

  Future<void> _setApplicationPolicy(
    ProcessConnectionGroup group,
    ApplicationRoutingPolicy policy,
  ) async {
    try {
      await perAppPolicyStore.setPolicy(
        processPath: group.processPath,
        name: group.name,
        policy: policy,
      );
      await globalState.appController.applyProfile();
      if (mounted) {
        setState(() {});
        await context.showNotifier(appLocalizations.successTitle);
      }
    } catch (error) {
      connectionDiagnostics.log(
        '[ConnectionsDiag] perApp.update status=error '
        'errorType=${error.runtimeType}',
      );
      if (mounted) {
        await context.showNotifier('ERROR: ${error.runtimeType}');
      }
    }
  }

  Widget _connectionList(
    List<TrackedConnection> items,
    AppSettingProps settings,
  ) {
    if (items.isEmpty) {
      return NullStatus(
        label: appLocalizations.nullTip(
          _status == _ConnectionStatusTab.active
              ? appLocalizations.connectionsActive
              : appLocalizations.connectionsClosed,
        ),
      );
    }
    if (settings.connectionViewMode == ConnectionViewMode.table) {
      return ConnectionTable(
        items: items,
        columns: settings.connectionTableColumns,
        columnWidths: settings.connectionTableColumnWidths,
        onColumnWidthsChanged: (widths) {
          ref.read(appSettingProvider.notifier).updateState(
                (value) => value.copyWith(connectionTableColumnWidths: widths),
              );
        },
        onTap: _showDetail,
        onClose: _closeItem,
      );
    }
    return ListView.builder(
      itemExtent: kConnRowExtent,
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        return TrackedConnectionRow(
          key: ValueKey(item.connection.id),
          item: item,
          showIcon: settings.connectionShowIcon,
          useApplicationName: settings.connectionUseApplicationName,
          onTap: () => _showDetail(item),
          onClose: () => _closeItem(item),
        );
      },
    );
  }

  void _showDetail(TrackedConnection item) {
    showConnectionDetail(
      context,
      item,
      onClose: item.isActive
          ? () => unawaited(
                connectionManager.closeConnection(item.connection.id),
              )
          : null,
    );
  }

  void _closeItem(TrackedConnection item) {
    if (item.isActive) {
      unawaited(connectionManager.closeConnection(item.connection.id));
    } else {
      connectionManager.removeClosed(item.connection.id);
    }
  }

  List<TrackedConnection> _connectionsFor(ProcessConnectionGroup? group) {
    if (group == null) {
      return _status == _ConnectionStatusTab.active
          ? connectionManager.activeConnections
          : connectionManager.closedConnections;
    }
    return _status == _ConnectionStatusTab.active
        ? group.activeConnections
        : group.closedConnections;
  }
}

List<ProcessConnectionGroup> _filteredGroups(
  List<ProcessConnectionGroup> groups,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return groups;
  return groups.where((group) {
    if (group.name.toLowerCase().contains(normalized) ||
        group.processPath.toLowerCase().contains(normalized)) {
      return true;
    }
    return group.activeConnections.any(
          (item) => trackedConnectionMatchesNormalizedQuery(item, normalized),
        ) ||
        group.closedConnections.any(
          (item) => trackedConnectionMatchesNormalizedQuery(item, normalized),
        );
  }).toList(growable: false);
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.activeCount,
    required this.closedCount,
    required this.upload,
    required this.download,
    required this.uploadSpeed,
    required this.downloadSpeed,
  });

  final int activeCount;
  final int closedCount;
  final num upload;
  final num download;
  final double uploadSpeed;
  final double downloadSpeed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Row(
          children: [
            _metric(
              context,
              Icons.hub_outlined,
              '$activeCount / $closedCount',
              '${appLocalizations.connectionsActive} / ${appLocalizations.connectionsClosed}',
            ),
            const SizedBox(width: 16),
            _metric(
              context,
              Icons.arrow_upward_rounded,
              connectionRate(uploadSpeed),
              TrafficValue(value: upload.toInt()).show,
            ),
            const SizedBox(width: 16),
            _metric(
              context,
              Icons.arrow_downward_rounded,
              connectionRate(downloadSpeed),
              TrafficValue(value: download.toInt()).show,
            ),
          ],
        ),
      );

  Widget _metric(
    BuildContext context,
    IconData icon,
    String value,
    String caption,
  ) =>
      Expanded(
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PauseButton extends StatelessWidget {
  const _PauseButton();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: connectionManager,
        builder: (_, __) => IconButton(
          tooltip: connectionManager.paused
              ? appLocalizations.connectionsResume
              : appLocalizations.connectionsPause,
          onPressed: () => connectionManager.setPaused(
            paused: !connectionManager.paused,
          ),
          icon: Icon(
            connectionManager.paused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
          ),
        ),
      );
}

class _ZashboardButton extends ConsumerWidget {
  const _ZashboardButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inApp = ref.watch(
      appSettingProvider.select((state) => state.zashboardInApp),
    );
    return IconButton(
      tooltip: 'zashboard',
      onPressed: () => openZashboard(context, inApp: inApp),
      icon: SvgPicture.asset(
        'assets/images/icons/zashboard.svg',
        width: 20,
        height: 20,
        colorFilter: ColorFilter.mode(
          context.colorScheme.onSurfaceVariant,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
