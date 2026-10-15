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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Keeps the existing view mounted only when its scope is selected. A disabled
/// feature or a single profile always follows the original proxy page path.
class NodeOverviewScopeView extends ConsumerWidget {
  const NodeOverviewScopeView({super.key, required this.currentView});

  final Widget currentView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(nodeOverviewEnabledProvider);
    final count = ref.watch(profilesProvider.select((value) => value.length));
    if (!enabled || count < 2) return currentView;
    final scope = ref.watch(proxiesScopeProvider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SegmentedButton<ProxiesScope>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: ProxiesScope.current,
                label: Text(appLocalizations.nodeOverviewCurrentProfile)),
            ButtonSegment(
                value: ProxiesScope.all,
                label: Text(appLocalizations.nodeOverviewAllProfiles)),
          ],
          selected: {scope},
          onSelectionChanged: (value) =>
              ref.read(proxiesScopeProvider.notifier).state = value.single,
        ),
      ),
      Expanded(
          child: scope == ProxiesScope.all
              ? const NodeOverviewView()
              : currentView),
    ]);
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
    final cached = ref.watch(cachedProfileCatalogsProvider);
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
                    return Card(
                        child: InkWell(
                      key: ValueKey('overview-select-${profile.id}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _selectedProfile = profile.id;
                        _expanded.add(profile.id);
                      }),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(profile.label ?? profile.id,
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              if (profile.id == activeId)
                                Text(appLocalizations.nodeOverviewActive),
                              _HealthSummary(
                                  profile: profile,
                                  catalog: cached[profile.id],
                                  now: now),
                            ],
                          )),
                    ));
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

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection(
      {required this.profile,
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
  Widget build(BuildContext context, WidgetRef ref) {
    // A collapsed section and the sidebar never initiate an IPC/script parse.
    final loaded =
        expanded ? ref.watch(profileCatalogProvider(profile.id)) : null;
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
            (!availableOnly || (health[node.identityKey]?.delayMs ?? -1) > 0))
        .toList();
    _sortNodes(nodes, health, sort);
    return SliverMainAxisGroup(slivers: [
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
                            style: Theme.of(context).textTheme.titleMedium)),
                    if (active)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(appLocalizations.nodeOverviewActive)),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  ]),
                  const SizedBox(height: 6),
                  _HealthSummary(profile: profile, catalog: catalog, now: now),
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
              catalog: catalog,
              health: health,
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
                  health: health[nodes[index].identityKey],
                  now: now),
            ),
          )
        else if (catalog?.status == ProfileCatalogStatus.ready)
          _notice(appLocalizations.nodeOverviewNoNodes),
        if (!active && catalog != null)
          for (final provider in catalog.providerNodeCounts.entries)
            _notice(appLocalizations.nodeOverviewProviderPending(provider.key)),
      ],
    ]);
  }

  Widget _notice(String text) => SliverToBoxAdapter(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(text)));
}

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
          health[a.identityKey]?.delayMs, health[b.identityKey]?.delayMs);
      if (result != 0) return result;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

bool _isLeaf(Proxy proxy, Set<String> groupNames) =>
    !groupNames.contains(proxy.name) &&
    !{'direct', 'reject', 'reject-drop', 'pass', 'dns', 'compatible'}
        .contains(proxy.type.toLowerCase());

class _ActiveNodes extends ConsumerWidget {
  const _ActiveNodes(
      {required this.catalog,
      required this.health,
      required this.query,
      required this.availableOnly,
      required this.now,
      required this.sort});

  final ProfileCatalog? catalog;
  final Map<String, NodeHealthRecord> health;
  final String query;
  final bool availableOnly;
  final DateTime now;
  final ProxiesSortType sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(currentGroupsStateProvider).value;
    final groupNames = ref.watch(groupsProvider).map((g) => g.name).toSet();
    final cardType =
        ref.watch(proxiesStyleSettingProvider.select((s) => s.cardType));
    ref.watch(delayDataSourceProvider);
    final inline = {
      for (final node in catalog?.nodes ?? <CatalogNode>[]) node.name: node
    };
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
            final node = inline[proxy.name];
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
                            '${node != null && health[node.identityKey] != null ? ' · ${_testedAt(health[node.identityKey]!, now, historical: false)}' : ''}',
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
    final record = health;
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
    if (catalog == null || catalog!.status == ProfileCatalogStatus.loading) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [...status, const Text('—')]);
    }
    if (catalog!.status == ProfileCatalogStatus.fileMissing ||
        catalog!.status == ProfileCatalogStatus.parseFailed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...status,
        Text(catalog!.status == ProfileCatalogStatus.fileMissing
            ? appLocalizations.nodeOverviewFileMissing
            : catalog!.errorSummary == 'tooManyNodes'
                ? appLocalizations.nodeOverviewTooManyNodes
                : appLocalizations.nodeOverviewParseFailed),
      ]);
    }
    final records = catalog!.nodes
        .map((node) => entries[node.identityKey])
        .whereType<NodeHealthRecord>()
        .toList();
    final delays = <int>[];
    var total = catalog!.nodes.length;
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
      delays.addAll(leaves.values
          .map((entry) => ref.watch(getDelayProvider(
              proxyName: entry.proxy.name, testUrl: entry.testUrl)))
          .whereType<int>()
          .where((d) => d != 0));
    } else {
      delays.addAll(records.map((record) => record.delayMs));
    }
    final success = delays.where((d) => d > 0).toList()..sort();
    final median = success.isEmpty
        ? '—'
        : '${success.length.isOdd ? success[success.length ~/ 2] : ((success[success.length ~/ 2 - 1] + success[success.length ~/ 2]) / 2).round()} ms';
    records.sort((a, b) => b.testedAt.compareTo(a.testedAt));
    final bands = [
      success.where((d) => d < 600).length,
      success.where((d) => d >= 600).length,
      delays.where((d) => d < 0).length,
      if (total > delays.length) total - delays.length else 0
    ];
    final colors = [
      utils.getDelayColor(100)!,
      utils.getDelayColor(800)!,
      utils.getDelayColor(-1)!,
      Theme.of(context).colorScheme.surfaceContainerHighest
    ];
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
                    for (var i = 0; i < bands.length; i++)
                      if (bands[i] > 0)
                        Expanded(
                            flex: bands[i],
                            child: Container(height: 5, color: colors[i])),
                  ])),
            )),
    ]);
  }
}
