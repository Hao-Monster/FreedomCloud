import 'dart:math';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'common.dart';

typedef GroupNameProxiesMap = Map<String, List<Proxy>>;

class ProxiesListView extends StatefulWidget {
  const ProxiesListView({super.key});

  @override
  State<ProxiesListView> createState() => _ProxiesListViewState();
}

class _ProxiesListViewState extends State<ProxiesListView> {
  final _controller = ScrollController();
  final _headerStateNotifier = ValueNotifier<ProxiesListHeaderSelectorState>(
    const ProxiesListHeaderSelectorState(
      offset: 0,
      currentIndex: 0,
    ),
  );
  final List<double> _headerOffset = [];
  GroupNameProxiesMap _lastGroupNameProxiesMap = {};

  int _lastGroupsVersion = 0;
  List<String> _lastGroupNames = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_adjustHeader);
  }

  void _adjustHeader() {
    final offset = _controller.offset;
    final index = _headerOffset.findInterval(offset);
    final currentIndex = index;
    var headerOffset = 0.0;
    if (index + 1 <= _headerOffset.length - 1) {
      final endOffset = _headerOffset[index + 1];
      final startOffset = endOffset - listHeaderHeight - 8;
      if (offset > startOffset && offset < endOffset) {
        headerOffset = offset - startOffset;
      }
    }
    _headerStateNotifier.value = _headerStateNotifier.value.copyWith(
      currentIndex: currentIndex,
      offset: max(headerOffset, 0),
    );
  }

  @override
  void dispose() {
    _headerStateNotifier.dispose();
    _controller
      ..removeListener(_adjustHeader)
      ..dispose();
    super.dispose();
  }

  List<Widget> _buildSlivers(
    WidgetRef ref, {
    required List<String> groupNames,
    required int columns,
    required Set<String> currentUnfoldSet,
    required ProxyCardType type,
    required String query,
  }) {
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
    final groupNameProxiesMap = <String, List<Proxy>>{};
    final safeColumns = max(1, columns);
    final rowGap = type == ProxyCardType.oneline ? 4.0 : 8.0;

    for (final groupName in groupNames) {
      final group = ref.watch(
        groupsProvider.select(
          (state) => state.getGroup(groupName),
        ),
      );
      if (group == null) {
        continue;
      }
      final isExpanded = currentUnfoldSet.contains(groupName);
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _ProxyGroupHeader(
              key: ValueKey('proxy-group-header-$groupName'),
              group: group,
              isExpanded: isExpanded,
            ),
          ),
        ),
      );

      if (!isExpanded) {
        continue;
      }

      final filteredProxies = query.isEmpty
          ? group.all
          : group.all
              .where((item) => item.name.toLowerCase().contains(query))
              .toList(growable: false);
      final sortedProxies = globalState.appController.getSortProxies(
        filteredProxies,
        group.testUrl,
      );
      groupNameProxiesMap[groupName] = sortedProxies;
      if (sortedProxies.isEmpty) {
        continue;
      }

      final rowCount = (sortedProxies.length + safeColumns - 1) ~/ safeColumns;
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: SliverList.builder(
            itemCount: rowCount,
            itemBuilder: (_, rowIndex) {
              final start = rowIndex * safeColumns;
              final end = min(start + safeColumns, sortedProxies.length);
              final rowChildren = <Widget>[];
              for (var col = 0; col < safeColumns; col++) {
                if (col > 0) {
                  rowChildren.add(const SizedBox(width: 8));
                }
                final idx = start + col;
                if (idx < end) {
                  final proxy = sortedProxies[idx];
                  rowChildren.add(
                    Flexible(
                      flex: 1,
                      child: RepaintBoundary(
                        child: ProxyCard(
                          testUrl: group.testUrl,
                          type: type,
                          groupType: group.type,
                          key: ValueKey('$groupName.${proxy.name}'),
                          proxy: proxy,
                          groupName: groupName,
                        ),
                      ),
                    ),
                  );
                } else {
                  rowChildren.add(
                    const Flexible(
                      child: SizedBox(),
                    ),
                  );
                }
              }
              final row = Row(children: rowChildren);
              if (rowIndex == 0) {
                return row;
              }
              return Padding(
                padding: EdgeInsets.only(top: rowGap),
                child: row,
              );
            },
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
    _lastGroupNameProxiesMap = groupNameProxiesMap;
    return slivers;
  }

  @override
  Widget build(BuildContext context) => Consumer(
        builder: (_, ref, __) {
          final state = ref.watch(proxiesListSelectorStateProvider);
          final groupsVersion = ref.watch(versionProvider);
          ref.watch(themeSettingProvider.select((state) => state.textScale));

          if (_lastGroupsVersion != groupsVersion ||
              !listEquals(_lastGroupNames, state.groupNames)) {
            _lastGroupsVersion = groupsVersion;
            _lastGroupNames = state.groupNames;
            _lastGroupNameProxiesMap.clear();
          }

          if (state.groupNames.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.proxies),
            );
          }
          final slivers = _buildSlivers(
            ref,
            groupNames: state.groupNames,
            currentUnfoldSet: state.currentUnfoldSet,
            columns: state.columns,
            type: state.proxyCardType,
            query: state.query,
          );
          return RepaintBoundary(
            child: CommonScrollBar(
              controller: _controller,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ScrollConfiguration(
                      behavior: HiddenBarScrollBehavior(),
                      child: FocusTraversalGroup(
                        policy: WidgetOrderTraversalPolicy(),
                        child: CustomScrollView(
                          controller: _controller,
                          slivers: slivers,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

String _resolveGroupIcon(
  Map<String, String> iconMap,
  String groupName,
  String defaultIcon,
) {
  if (iconMap.isEmpty) return defaultIcon;
  for (final entry in iconMap.entries) {
    try {
      if (RegExp(entry.key).hasMatch(groupName)) {
        return entry.value;
      }
    } catch (_) {}
  }
  return defaultIcon;
}

class _ProxyGroupHeader extends ConsumerStatefulWidget {
  const _ProxyGroupHeader({
    super.key,
    required this.group,
    required this.isExpanded,
  });

  final Group group;
  final bool isExpanded;

  @override
  ConsumerState<_ProxyGroupHeader> createState() => _ProxyGroupHeaderState();
}

class _ProxyGroupHeaderState extends ConsumerState<_ProxyGroupHeader> {
  bool _isLock = false;

  String get groupName => widget.group.name;

  void _toggleExpansion() {
    final unfoldSet = Set<String>.from(ref.read(unfoldSetProvider));
    if (widget.isExpanded) {
      unfoldSet.remove(groupName);
    } else {
      unfoldSet.add(groupName);
    }
    globalState.appController.updateCurrentUnfoldSet(unfoldSet);
  }

  Future<void> _delayTest() async {
    if (_isLock) return;
    _isLock = true;
    try {
      await delayTest(widget.group.all, widget.group.testUrl);
    } finally {
      _isLock = false;
    }
  }

  Widget _buildIcon() {
    final iconStyle = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.iconStyle),
    );
    if (iconStyle == ProxiesIconStyle.none) {
      return const SizedBox.shrink();
    }
    final icon = ref.watch(
      proxiesStyleSettingProvider.select(
        (state) => _resolveGroupIcon(state.iconMap, groupName, widget.group.icon),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: CommonTargetIcon(
        src: icon,
        size: 38,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _toggleExpansion,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow.opacity80,
            borderRadius: BorderRadius.circular(16.0),
          ),
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          padding: const EdgeInsets.symmetric(
            vertical: 10.0,
            horizontal: 16.0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    _buildIcon(),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groupName,
                            style: context.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Flexible(
                            flex: 1,
                            child: Consumer(
                              builder: (_, ref, __) {
                                final proxyName = ref
                                    .watch(getSelectedProxyNameProvider(groupName))
                                    .getSafeValue('');
                                if (proxyName.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return EmojiText(
                                  overflow: TextOverflow.ellipsis,
                                  proxyName,
                                  style: context.textTheme.labelMedium?.toLight,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  ListenableBuilder(
                    listenable: delayTests,
                    builder: (_, __) => IconButton(
                      onPressed: delayTests.busy ? null : _delayTest,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 40, height: 40),
                      icon: const Icon(Icons.network_ping),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: _toggleExpansion,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 40, height: 40),
                    icon: CommonExpandIcon(expand: widget.isExpanded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProxyGroupCard extends StatefulWidget {
  const ProxyGroupCard({
    super.key,
    required this.group,
    required this.proxies,
  });
  final Group group;
  final List<Widget> proxies;

  @override
  State<ProxyGroupCard> createState() => _ProxyGroupCardState();
}

class _ProxyGroupCardState extends State<ProxyGroupCard>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer(
      builder: (_, ref, __) {
        final shouldExpand = ref.watch(
          unfoldSetProvider.select((s) => s.contains(widget.group.name)),
        );
        return RepaintBoundary(
          child: Column(
            children: [
              _ProxyGroupHeader(
                group: widget.group,
                isExpanded: shouldExpand,
              ),
              if (shouldExpand)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Column(children: widget.proxies),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
