import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/node_health_store.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/models/node_catalog.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/proxies/card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Selects only the page body; the scope control belongs to the existing app bar.
class NodeOverviewScopeView extends ConsumerWidget {
  const NodeOverviewScopeView({super.key, required this.currentView});

  final Widget currentView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(nodeOverviewEnabledProvider);
    final count = ref.watch(profilesProvider.select((value) => value.length));
    if (!enabled || count < 2) return currentView;
    final scope = ref.watch(proxiesScopeProvider);
    return scope == ProxiesScope.all ? const NodeOverviewView() : currentView;
  }
}

class NodeOverviewScopeAction extends ConsumerWidget {
  const NodeOverviewScopeAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(nodeOverviewEnabledProvider);
    final count = ref.watch(profilesProvider.select((value) => value.length));
    if (!enabled || count < 2) return const SizedBox.shrink();
    final scope = ref.watch(proxiesScopeProvider);
    final labels = {
      ProxiesScope.current: appLocalizations.nodeOverviewCurrentProfile,
      ProxiesScope.all: appLocalizations.nodeOverviewAllProfiles,
    };
    void select(ProxiesScope value) =>
        ref.read(proxiesScopeProvider.notifier).state = value;
    if (ref.watch(viewWidthProvider) <= maxLaptopWidth) {
      return PopupMenuButton<ProxiesScope>(
        key: const ValueKey('overview-scope-menu'),
        tooltip: labels[scope],
        icon: Icon(
            scope == ProxiesScope.all ? Icons.layers : Icons.layers_outlined),
        onSelected: select,
        itemBuilder: (context) => [
          for (final value in ProxiesScope.values)
            CheckedPopupMenuItem(
                value: value,
                checked: scope == value,
                child: Text(labels[value]!)),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<ProxiesScope>(
        key: const ValueKey('overview-scope-segments'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final value in ProxiesScope.values)
            ButtonSegment(value: value, label: Text(labels[value]!))
        ],
        selected: {scope},
        onSelectionChanged: (value) => select(value.single),
      ),
    );
  }
}

class NodeOverviewView extends ConsumerStatefulWidget {
  const NodeOverviewView({super.key});

  @override
  ConsumerState<NodeOverviewView> createState() => _NodeOverviewViewState();
}

class _NodeOverviewViewState extends ConsumerState<NodeOverviewView> {
  final _expanded = <String>{};
  String? _selectedProfile;
  bool _availableOnly = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    final activeId = ref.read(currentProfileIdProvider);
    if (activeId != null) _expanded.add(activeId);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _toggle(String id) => setState(() {
        if (!_expanded.remove(id)) _expanded.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(currentProfileIdProvider);
    final mobile = ref.watch(isMobileViewProvider);
    final sort =
        ref.watch(proxiesStyleSettingProvider.select((s) => s.sortType));
    // Explicit search may inspect every saved profile. Ordinary browsing keeps
    // unopened profiles lazy, and clearing search restores manual expansion.
    final searching = ref.watch(proxiesQueryProvider).trim().isNotEmpty;
    final selected =
        profiles.any((p) => p.id == _selectedProfile) ? _selectedProfile : null;
    final now = DateTime.now();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                    label: Text(appLocalizations.nodeOverviewAvailableOnly),
                    selected: _availableOnly,
                    onSelected: (value) =>
                        setState(() => _availableOnly = value)),
                DropdownButton<ProxiesSortType>(
                  value: sort,
                  items: [
                    DropdownMenuItem(
                        value: ProxiesSortType.none,
                        child: Text(appLocalizations.defaultText)),
                    DropdownMenuItem(
                        value: ProxiesSortType.name,
                        child: Text(appLocalizations.name)),
                    DropdownMenuItem(
                        value: ProxiesSortType.delay,
                        child: Text(appLocalizations.delay)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(proxiesStyleSettingProvider.notifier)
                          .updateState(
                              (state) => state.copyWith(sortType: value));
                    }
                  },
                ),
              ],
            )),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Text(appLocalizations.nodeOverviewHistoryNotice,
                style: Theme.of(context).textTheme.bodySmall)),
      ),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final wide = !mobile && constraints.maxWidth > maxLaptopWidth;
        final visible = wide && selected != null && !searching
            ? profiles.where((p) => p.id == selected).toList()
            : profiles;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (wide) ...[
            SizedBox(
                width: 290,
                child: ListView.builder(
                  key: const ValueKey('overview-sidebar'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 0, 16),
                  itemCount: profiles.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                          title: Text(appLocalizations.nodeOverviewAllProfiles),
                          selected: selected == null,
                          onTap: () => setState(() => _selectedProfile = null));
                    }
                    final profile = profiles[index - 1];
                    return _SidebarProfileCard(
                      profile: profile,
                      active: profile.id == activeId,
                      now: now,
                      onSelect: () => setState(() {
                        _selectedProfile = profile.id;
                        _expanded.add(profile.id);
                      }),
                    );
                  },
                )),
            const VerticalDivider(width: 16),
          ],
          Expanded(
              child: CustomScrollView(
            key: const ValueKey('overview-nodes'),
            slivers: [
              for (final profile in visible)
                _ProfileSection(
                    key: ValueKey('overview-section-${profile.id}'),
                    profile: profile,
                    active: profile.id == activeId,
                    expanded: searching || _expanded.contains(profile.id),
                    availableOnly: _availableOnly,
                    now: now,
                    onToggle: searching ? null : () => _toggle(profile.id)),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          )),
        ]);
      })),
    ]);
  }
}

class _SidebarProfileCard extends ConsumerWidget {
  const _SidebarProfileCard(
      {required this.profile,
      required this.active,
      required this.now,
      required this.onSelect});
  final Profile profile;
  final bool active;
  final DateTime now;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ListView builds only the visible/cached sidebar rows. Share the same
    // family future with the main section instead of starting a second parse.
    final loaded = ref.watch(profileCatalogProvider(profile.id));
    final catalog = loaded.valueOrNull ??
        ref.watch(cachedProfileCatalogsProvider)[profile.id];
    return Card(
        child: InkWell(
      key: ValueKey('overview-select-${profile.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onSelect,
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.label ?? profile.id,
                  style: Theme.of(context).textTheme.titleSmall),
              if (active) Text(appLocalizations.nodeOverviewActive),
              _HealthSummary(profile: profile, catalog: catalog, now: now),
            ],
          )),
    ));
  }
}

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection(
      {super.key,
      required this.profile,
      required this.active,
      required this.expanded,
      required this.availableOnly,
      required this.now,
      required this.onToggle});

  final Profile profile;
  final bool active;
  final bool expanded;
  final bool availableOnly;
  final DateTime now;
  final VoidCallback? onToggle;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  bool _visible = false;
  bool _nextVisible = false;
  bool _visibilityScheduled = false;

  Profile get profile => widget.profile;
  bool get active => widget.active;
  bool get expanded => widget.expanded;
  bool get availableOnly => widget.availableOnly;
  DateTime get now => widget.now;
  VoidCallback? get onToggle => widget.onToggle;

  void _visibilityChanged(bool value) {
    _nextVisible = value;
    if (_visibilityScheduled || _visible == value) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (mounted && _visible != _nextVisible) {
        setState(() => _visible = _nextVisible);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Slivers outside the viewport retain their small header but do not parse a
    // profile. Explicit expansion/search still opts into loading offscreen data.
    final loaded = expanded || _visible
        ? ref.watch(profileCatalogProvider(profile.id))
        : null;
    final catalog = loaded?.valueOrNull ??
        ref.watch(cachedProfileCatalogsProvider)[profile.id];
    final health = ref.watch(nodeHealthEntriesProvider(profile.id));
    final query = ref.watch(proxiesQueryProvider).trim().toLowerCase();
    final sort =
        ref.watch(proxiesStyleSettingProvider.select((s) => s.sortType));
    final profileMatches =
        (profile.label ?? profile.id).toLowerCase().contains(query);
    final nodes = (catalog?.nodes ?? <CatalogNode>[])
        .where((node) =>
            (profileMatches || _matches(node, query)) &&
            (!availableOnly || (_nodeHealth(node, health)?.delayMs ?? -1) > 0))
        .toList();
    _sortNodes(nodes, health, sort);
    return _PaintVisibilitySliver(
        onVisibilityChanged: _visibilityChanged,
        child: SliverMainAxisGroup(slivers: [
          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Card(
                child: InkWell(
              key: ValueKey('overview-header-${profile.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: onToggle,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(profile.label ?? profile.id,
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        if (active)
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(appLocalizations.nodeOverviewActive)),
                        Icon(expanded ? Icons.expand_less : Icons.expand_more),
                      ]),
                      const SizedBox(height: 6),
                      _HealthSummary(
                          profile: profile, catalog: catalog, now: now),
                    ],
                  )),
            )),
          )),
          if (expanded) ...[
            if (((loaded?.isLoading ?? false) && catalog == null) ||
                catalog?.status == ProfileCatalogStatus.loading)
              const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator())),
            if (loaded?.hasError ?? false)
              _notice(appLocalizations.nodeOverviewParseFailed),
            if (_expired(profile, now) ||
                (loaded?.hasError ?? false) ||
                catalog?.status == ProfileCatalogStatus.fileMissing ||
                catalog?.status == ProfileCatalogStatus.parseFailed)
              SliverToBoxAdapter(
                  child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextButton.icon(
                      onPressed: () =>
                          globalState.appController.toPage(PageLabel.profiles),
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: Text(appLocalizations.nodeOverviewManageProfiles),
                    )),
              )),
            if (active)
              _ActiveNodes(
                  query: profileMatches ? '' : query,
                  availableOnly: availableOnly,
                  now: now,
                  sort: sort)
            else if (nodes.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: nodes.length,
                  itemBuilder: (context, index) => _InactiveNodeRow(
                      key: ValueKey(
                          'overview-node-${profile.id}-${nodes[index].identityKey}'),
                      node: nodes[index],
                      health: _nodeHealth(nodes[index], health),
                      now: now),
                ),
              )
            else if (catalog?.status == ProfileCatalogStatus.ready)
              _notice(appLocalizations.nodeOverviewNoNodes),
            if (!active && catalog != null)
              for (final provider in catalog.providerNodeCounts.entries)
                _notice(
                    appLocalizations.nodeOverviewProviderPending(provider.key)),
          ],
        ]));
  }

  Widget _notice(String text) => SliverToBoxAdapter(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(text)));
}

/// A sliver's painted geometry is the viewport authority; mounted headers alone
/// are insufficient because CustomScrollView mounts every section sliver.
class _PaintVisibilitySliver extends SingleChildRenderObjectWidget {
  const _PaintVisibilitySliver(
      {required this.onVisibilityChanged, required super.child});
  final ValueChanged<bool> onVisibilityChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintVisibilitySliver(onVisibilityChanged);

  @override
  void updateRenderObject(
      BuildContext context, _RenderPaintVisibilitySliver renderObject) {
    renderObject.onVisibilityChanged = onVisibilityChanged;
  }
}

class _RenderPaintVisibilitySliver extends RenderProxySliver {
  _RenderPaintVisibilitySliver(this.onVisibilityChanged);
  ValueChanged<bool> onVisibilityChanged;
  bool? _visible;

  @override
  void performLayout() {
    super.performLayout();
    final visible = geometry?.visible ?? false;
    if (_visible != visible) {
      _visible = visible;
      onVisibilityChanged(visible);
    }
  }
}

NodeHealthRecord? _nodeHealth(
        CatalogNode node, Map<String, NodeHealthRecord> health) =>
    node.unsupported == CatalogUnsupportedReason.parseFailed
        ? null
        : health[node.identityKey];

bool _expired(Profile profile, DateTime now) {
  final expire = profile.subscriptionInfo?.expire ?? 0;
  return expire > 0 && expire * 1000 <= now.millisecondsSinceEpoch;
}

bool _matches(CatalogNode node, String query) =>
    '${node.name}\n${node.type}\n${node.providerName ?? ''}'
        .toLowerCase()
        .contains(query);

int _compareDelay(int? a, int? b) {
  final aRank = a != null && a > 0 ? a : 1 << 62;
  final bRank = b != null && b > 0 ? b : 1 << 62;
  return aRank.compareTo(bRank);
}

void _sortNodes(List<CatalogNode> nodes, Map<String, NodeHealthRecord> health,
    ProxiesSortType sort) {
  if (sort == ProxiesSortType.none) return;
  nodes.sort((a, b) {
    if (sort == ProxiesSortType.delay) {
      final result = _compareDelay(
          _nodeHealth(a, health)?.delayMs, _nodeHealth(b, health)?.delayMs);
      if (result != 0) return result;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

bool _isLeaf(Proxy proxy, Set<String> groupNames) =>
    !groupNames.contains(proxy.name) &&
    !{'direct', 'reject', 'reject-drop', 'pass', 'dns', 'compatible'}
        .contains(proxy.type.toLowerCase());

Map<String, CatalogNode> _uniqueCatalogNodes(ProfileCatalog? catalog) {
  final counts = <String, int>{};
  for (final node in catalog?.nodes ?? <CatalogNode>[]) {
    counts.update(node.name, (count) => count + 1, ifAbsent: () => 1);
  }
  return {
    for (final node in catalog?.nodes ?? <CatalogNode>[])
      if (counts[node.name] == 1 &&
          node.unsupported != CatalogUnsupportedReason.parseFailed)
        node.name: node
  };
}

Map<String, NodeHealthRecord> _activeHealthForUrl(
    WidgetRef ref, String profileId, String? testUrl) {
  final effectiveUrl = ref.watch(getRealTestUrlProvider(testUrl));
  if (effectiveUrl == ref.watch(nodeOverviewTestUrlProvider)) {
    return ref.watch(nodeHealthEntriesProvider(profileId));
  }
  // Card delays resolve the group's effective URL. Read the same URL's history
  // so a default-URL timestamp cannot be attached to a custom-URL result.
  return ref
      .watch(nodeHealthStoreProvider)
      .readProfile(profileId, testUrl: effectiveUrl);
}

class _ActiveNodes extends ConsumerWidget {
  const _ActiveNodes(
      {required this.query,
      required this.availableOnly,
      required this.now,
      required this.sort});

  final String query;
  final bool availableOnly;
  final DateTime now;
  final ProxiesSortType sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(currentGroupsStateProvider).value;
    final catalog = ref.watch(activeNodeCatalogProvider);
    final groupNames = ref.watch(groupsProvider).map((g) => g.name).toSet();
    final cardType =
        ref.watch(proxiesStyleSettingProvider.select((s) => s.cardType));
    ref.watch(delayDataSourceProvider);
    final runtimeNodes = _uniqueCatalogNodes(catalog);
    final histories = <String?, Map<String, NodeHealthRecord>>{};
    final rows = <({Group group, Proxy? proxy})>[];
    for (final group in groups) {
      final proxies = group.all.where((proxy) {
        if (!_isLeaf(proxy, groupNames)) return false;
        if (!'${proxy.name}\n${proxy.type}'.toLowerCase().contains(query)) {
          return false;
        }
        return !availableOnly ||
            (ref.read(getDelayProvider(
                        proxyName: proxy.name, testUrl: group.testUrl)) ??
                    -1) >
                0;
      }).toList();
      if (sort != ProxiesSortType.none) {
        proxies.sort((a, b) {
          if (sort == ProxiesSortType.delay) {
            final result = _compareDelay(
                ref.read(getDelayProvider(
                    proxyName: a.name, testUrl: group.testUrl)),
                ref.read(getDelayProvider(
                    proxyName: b.name, testUrl: group.testUrl)));
            if (result != 0) return result;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      }
      if (proxies.isEmpty) continue;
      if (catalog != null && runtimeNodes.isNotEmpty) {
        histories.putIfAbsent(group.testUrl,
            () => _activeHealthForUrl(ref, catalog.profileId, group.testUrl));
      }
      rows
        ..add((group: group, proxy: null))
        ..addAll(proxies.map((proxy) => (group: group, proxy: proxy)));
    }
    if (rows.isEmpty) {
      return SliverToBoxAdapter(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(appLocalizations.nodeOverviewNoNodes)));
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final proxy = row.proxy;
            if (proxy == null) {
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(row.group.name,
                      style: Theme.of(context).textTheme.titleSmall));
            }
            final node = runtimeNodes[proxy.name];
            final history = node == null
                ? null
                : _nodeHealth(node, histories[row.group.testUrl] ?? const {});
            return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProxyCard(
                        key: ValueKey(
                            'overview-active-${row.group.name}-${proxy.name}'),
                        groupName: row.group.name,
                        testUrl: row.group.testUrl,
                        proxy: proxy,
                        groupType: row.group.type,
                        type: cardType),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                        child: Text(
                            '${node == null ? appLocalizations.nodeOverviewRuntimeSource : _source(node)}'
                            '${history != null ? ' · ${_testedAt(history, now, historical: false)}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ));
          }),
    );
  }
}

String _source(CatalogNode node) => node.source == CatalogNodeSource.inline
    ? appLocalizations.nodeOverviewInline
    : node.providerName ?? appLocalizations.providers;

String _testedAt(NodeHealthRecord record, DateTime now,
    {required bool historical}) {
  final time = DateFormat.yMd().add_Hm().format(record.testedAt.toLocal());
  final label = historical
      ? appLocalizations.nodeOverviewLastActiveTest(time)
      : appLocalizations.nodeOverviewLastTest(time);
  return record.isStale(now)
      ? '$label · ${appLocalizations.nodeOverviewStale}'
      : label;
}

class _InactiveNodeRow extends StatelessWidget {
  const _InactiveNodeRow(
      {super.key, required this.node, required this.health, required this.now});
  final CatalogNode node;
  final NodeHealthRecord? health;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final invalid = node.unsupported == CatalogUnsupportedReason.parseFailed;
    final record = invalid ? null : health;
    final stale = record?.isStale(now) ?? false;
    final color = stale
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : utils.getDelayColor(record?.delayMs);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(node.name)),
                  const SizedBox(width: 12),
                  if (invalid)
                    Icon(Icons.help_outline,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)
                  else
                    Text(
                        record == null
                            ? appLocalizations.nodeOverviewUntested
                            : record.delayMs > 0
                                ? '${record.delayMs} ms'
                                : appLocalizations.nodeOverviewTestFailed,
                        style: TextStyle(color: color)),
                ]),
                const SizedBox(height: 4),
                Text('${node.type} · ${_source(node)}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (invalid)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(appLocalizations.nodeOverviewNodeUnidentified,
                          style: Theme.of(context).textTheme.bodySmall)),
                if (record != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_testedAt(record, now, historical: true),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: color))),
              ],
            )));
  }
}

class _HealthSummary extends ConsumerWidget {
  const _HealthSummary(
      {required this.profile, required this.catalog, required this.now});
  final Profile profile;
  final ProfileCatalog? catalog;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(nodeHealthEntriesProvider(profile.id));
    final active = ref.watch(currentProfileIdProvider) == profile.id;
    final status = <Widget>[
      if (_expired(profile, now)) Text(appLocalizations.nodeOverviewExpired),
      if (profile.isUpdating ||
          catalog?.status == ProfileCatalogStatus.updating)
        Text(appLocalizations.nodeOverviewUpdating),
    ];
    if (!active &&
        (catalog == null || catalog!.status == ProfileCatalogStatus.loading)) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [...status, const Text('—')]);
    }
    if (catalog?.status == ProfileCatalogStatus.fileMissing ||
        catalog?.status == ProfileCatalogStatus.parseFailed) {
      status.add(Text(catalog!.status == ProfileCatalogStatus.fileMissing
          ? appLocalizations.nodeOverviewFileMissing
          : catalog!.errorSummary == 'tooManyNodes'
              ? appLocalizations.nodeOverviewTooManyNodes
              : appLocalizations.nodeOverviewParseFailed));
      if (!active) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: status);
      }
    }
    final records = <NodeHealthRecord>[];
    final delays = <int>[];
    var total = catalog?.nodes.length ?? 0;
    if (active) {
      final groups = ref.watch(currentGroupsStateProvider).value;
      final names = ref.watch(groupsProvider).map((g) => g.name).toSet();
      final leaves = <String, ({Proxy proxy, String? testUrl})>{};
      for (final group in groups) {
        for (final proxy in group.all.where((proxy) => _isLeaf(proxy, names))) {
          // One node can occur in several groups with different test URLs.
          // Count it once, using the first visible card's test semantics.
          leaves.putIfAbsent(
              proxy.name, () => (proxy: proxy, testUrl: group.testUrl));
        }
      }
      total = leaves.length;
      final runtimeNodes =
          _uniqueCatalogNodes(ref.watch(activeNodeCatalogProvider));
      final histories = <String?, Map<String, NodeHealthRecord>>{};
      for (final entry in leaves.values) {
        final delay = ref.watch(getDelayProvider(
            proxyName: entry.proxy.name, testUrl: entry.testUrl));
        if (delay != null && delay != 0) delays.add(delay);
        final node = runtimeNodes[entry.proxy.name];
        if (node == null) continue;
        final health = histories.putIfAbsent(entry.testUrl,
            () => _activeHealthForUrl(ref, profile.id, entry.testUrl));
        final record = _nodeHealth(node, health);
        if (record != null) records.add(record);
      }
    } else {
      records.addAll((catalog?.nodes ?? <CatalogNode>[])
          .map((node) => _nodeHealth(node, entries))
          .whereType<NodeHealthRecord>());
      delays.addAll(records.map((record) => record.delayMs));
    }
    final success = delays.where((d) => d > 0).toList()..sort();
    final median = success.isEmpty
        ? '—'
        : '${success.length.isOdd ? success[success.length ~/ 2] : ((success[success.length ~/ 2 - 1] + success[success.length ~/ 2]) / 2).round()} ms';
    records.sort((a, b) => b.testedAt.compareTo(a.testedAt));
    // Group by the same color function as every node card, so future threshold
    // changes cannot leave the summary's proportions on an older scale.
    final bands = <Color, int>{};
    for (final delay in [...success, ...delays.where((delay) => delay < 0)]) {
      final color = utils.getDelayColor(delay)!;
      bands.update(color, (count) => count + 1, ifAbsent: () => 1);
    }
    if (total > delays.length) {
      bands[Theme.of(context).colorScheme.surfaceContainerHighest] =
          total - delays.length;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...status,
      Text(appLocalizations.nodeOverviewHealthCounts(
          success.length, delays.length, total)),
      if (!active && catalog!.providerNodeCounts.isNotEmpty)
        Text(appLocalizations.nodeOverviewPartialSummary,
            style: Theme.of(context).textTheme.bodySmall),
      Text(appLocalizations.nodeOverviewMedian(median)),
      if (records.isNotEmpty)
        Text(_testedAt(records.first, now, historical: !active),
            style: Theme.of(context).textTheme.bodySmall),
      if (total > 0)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              label: appLocalizations.nodeOverviewHealthCounts(
                  success.length, delays.length, total),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Row(children: [
                    for (final band in bands.entries)
                      Expanded(
                          flex: band.value,
                          child: Container(height: 5, color: band.key)),
                  ])),
            )),
    ]);
  }
}
