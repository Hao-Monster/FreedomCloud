import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/views/config/network.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<T?> _showRuleDialog<T>(BuildContext context, Widget dialog) {
  if (globalState.navigatorKey.currentState?.mounted == true) {
    return globalState.showCommonDialog<T>(child: dialog);
  }
  return showDialog<T>(
    context: context,
    builder: (_) => dialog,
  );
}

Future<bool> _confirmDeleteRules(BuildContext context) async {
  if (globalState.navigatorKey.currentState?.mounted == true) {
    final res = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: appLocalizations.deleteMultipTip(appLocalizations.rule),
      ),
    );
    return res == true;
  }
  final res = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => CommonDialog(
      title: appLocalizations.tip,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: Text(appLocalizations.deleteMultipTip(appLocalizations.rule)),
    ),
  );
  return res == true;
}

class GlobalOverrideView extends ConsumerStatefulWidget {
  const GlobalOverrideView({super.key});

  @override
  ConsumerState<GlobalOverrideView> createState() => _GlobalOverrideViewState();
}

class _GlobalOverrideViewState extends ConsumerState<GlobalOverrideView> {
  final _controller = ScrollController();
  Set<String> _selectedRules = {};
  double _currentMaxWidth = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ClashConfigSnippet _buildGlobalSnippet() {
    final runtimeGroups = ref.read(groupsProvider);
    final proxyGroups = <ProxyGroup>[
      for (final g in runtimeGroups)
        if (g.name.toUpperCase() != 'GLOBAL' && g.hidden != true)
          ProxyGroup(name: g.name, type: g.type),
    ];
    return ClashConfigSnippet(proxyGroups: proxyGroups);
  }

  void _commitGlobalOverride(OverrideData next) {
    ref.read(globalOverrideProvider.notifier).updateState((_) => next);
    globalState.appController.setupClashConfigDebounce();
    globalState.appController.savePreferencesDebounce();
  }

  Future<void> _handleAddOrEdit([Rule? existing]) async {
    final res = await _showRuleDialog<Rule>(
      context,
      AddRuleDialog(
        snippet: _buildGlobalSnippet(),
        rule: existing,
        isGlobal: true,
      ),
    );
    if (res == null || !mounted) {
      return;
    }
    final current = ref.read(globalOverrideProvider);
    final updatedRule = current.rule.copyWith(
      type: OverrideRuleType.added,
      addedRules: _upsertRule(current.rule.addedRules, res),
    );
    _commitGlobalOverride(
      current.copyWith(
        enable: existing == null ? true : current.enable,
        rule: updatedRule,
      ),
    );
  }

  Future<void> _handleDeleteSelected() async {
    if (_selectedRules.isEmpty) return;
    final confirmed = await _confirmDeleteRules(context);
    if (!confirmed || !mounted) return;
    final current = ref.read(globalOverrideProvider);
    final remaining = current.rule.addedRules
        .where((item) => !_selectedRules.contains(item.id))
        .toList();
    setState(() {
      _selectedRules = {};
    });
    _commitGlobalOverride(
      current.copyWith(
        rule: current.rule.copyWith(
          type: OverrideRuleType.added,
          addedRules: remaining,
        ),
      ),
    );
  }

  void _toggleSelect(String ruleId) {
    setState(() {
      final next = Set<String>.from(_selectedRules);
      if (!next.remove(ruleId)) {
        next.add(ruleId);
      }
      _selectedRules = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final overrideData = ref.watch(globalOverrideProvider);
    final rules = overrideData.rule.addedRules;
    final scriptMode = ref.watch(
      scriptStateProvider.select((state) => state.realId != null),
    );
    final editCount = _selectedRules.length;
    final isEdit = editCount > 0;
    final isSelectAll =
        rules.isNotEmpty && _selectedRules.containsAll(rules.map((r) => r.id));

    return CommonScaffold(
      disableBackground: true,
      title: appLocalizations.globalOverride,
      actions: [
        if (editCount == 1)
          IconButton(
            onPressed: () {
              final targetId = _selectedRules.first;
              final idx = rules.indexWhere((r) => r.id == targetId);
              if (idx != -1) {
                unawaited(_handleAddOrEdit(rules[idx]));
              }
            },
            icon: const Icon(Icons.edit),
          ),
        if (editCount > 0)
          IconButton(
            onPressed: _handleDeleteSelected,
            icon: const Icon(Icons.delete),
          ),
      ],
      appBarEditState: AppBarEditState(
        isEdit: isEdit,
        editCount: editCount,
        onExit: () {
          setState(() {
            _selectedRules = {};
          });
        },
      ),
      body: LayoutBuilder(
        builder: (_, constraints) {
          _currentMaxWidth =
              (constraints.maxWidth - 104).clamp(120.0, double.infinity);
          return CommonAutoHiddenScrollBar(
            controller: _controller,
            child: CustomScrollView(
              controller: _controller,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                if (scriptMode)
                  SliverToBoxAdapter(
                    child: ListItem(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 0,
                      ),
                      title: Row(
                        spacing: 8,
                        children: [
                          const Icon(Icons.info),
                          Text(appLocalizations.overrideInvalidTip),
                        ],
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: CommonCard(
                      onPressed: () {},
                      type: CommonCardType.filled,
                      radius: 18,
                      child: ListItem.switchItem(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(appLocalizations.enableGlobalOverride),
                        subtitle: Text(appLocalizations.overrideAutoSavedHint),
                        delegate: SwitchDelegate(
                          value: overrideData.enable,
                          onChanged: (value) {
                            _commitGlobalOverride(
                              overrideData.copyWith(enable: value),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: CommonCard(
                      onPressed: null,
                      type: CommonCardType.filled,
                      radius: 18,
                      child: const LocalSplitModeItem(),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _OverrideRuleHeaderBar(
                      subTitle: appLocalizations.globalOverrideDesc,
                      isEdit: isEdit,
                      isSelectAll: isSelectAll,
                      showTypeToggle: false,
                      isOverrideRule: false,
                      onToggleType: null,
                      onAdd: _handleAddOrEdit,
                      onToggleSelectAll: () {
                        setState(() {
                          _selectedRules = isSelectAll
                              ? {}
                              : rules.map((r) => r.id).toSet();
                        });
                      },
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _ReorderableRuleSliver(
                    rules: rules,
                    selectedRules: _selectedRules,
                    maxWidth: _currentMaxWidth,
                    cacheTag: CacheTag.rules,
                    emptyType: OverrideRuleType.added,
                    onTapRule: _toggleSelect,
                    onReorderRules: (newRules) {
                      _commitGlobalOverride(
                        overrideData.copyWith(
                          rule: overrideData.rule.copyWith(
                            type: OverrideRuleType.added,
                            addedRules: newRules,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          );
        },
      ),
    );
  }
}

List<Rule> _upsertRule(List<Rule> rules, Rule target) {
  final index = rules.indexWhere((item) => item.id == target.id);
  if (index == -1) {
    return <Rule>[target, ...rules];
  }
  final next = List<Rule>.from(rules);
  next[index] = target;
  return next;
}

class OverrideProfileView extends StatefulWidget {
  const OverrideProfileView({
    super.key,
    required this.profileId,
    this.loadProfileConfig,
  });

  final String profileId;
  final Future<Map<String, dynamic>> Function(String profileId)?
      loadProfileConfig;

  @override
  State<OverrideProfileView> createState() => _OverrideProfileViewState();
}

class _OverrideProfileViewState extends State<OverrideProfileView> {
  final _controller = ScrollController();
  double _currentMaxWidth = 0;
  bool _initScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _initState(WidgetRef ref) {
    if (_initScheduled) return;
    _initScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final loader = widget.loadProfileConfig ?? globalState.getProfileConfig;
      Map<String, dynamic> rawConfig;
      try {
        rawConfig = await loader(widget.profileId);
      } catch (_) {
        rawConfig = const <String, dynamic>{};
      }
      if (!mounted) return;
      final snippet = ClashConfigSnippet.fromJson(rawConfig);
      final overrideData =
          ref.read(getProfileOverrideDataProvider(widget.profileId)) ??
              const OverrideData();
      ref.read(profileOverrideStateProvider.notifier).updateState(
            (state) => state.copyWith(
              snippet: snippet,
              overrideData: overrideData,
            ),
          );
    });
  }

  void _commitProfileOverride(WidgetRef ref, OverrideData next) {
    ref.read(profileOverrideStateProvider.notifier).updateState(
          (state) => state.copyWith(overrideData: next),
        );
    ref.read(profilesProvider.notifier).updateProfile(
          widget.profileId,
          (profile) => profile.copyWith(overrideData: next),
        );
    globalState.appController.setupClashConfigDebounce();
    globalState.appController.savePreferencesDebounce();
  }

  Future<void> _handleAddOrEdit(WidgetRef ref, [Rule? existing]) async {
    final snippet = ref.read(
          profileOverrideStateProvider.select((state) => state.snippet),
        ) ??
        const ClashConfigSnippet();
    final res = await _showRuleDialog<Rule>(
      context,
      AddRuleDialog(
        snippet: snippet,
        rule: existing,
      ),
    );
    if (res == null || !mounted) return;
    final current = ref.read(
          profileOverrideStateProvider.select((state) => state.overrideData),
        ) ??
        const OverrideData();
    final nextRule = current.rule.updateRules(
      (rules) => _upsertRule(rules, res),
    );
    _commitProfileOverride(
      ref,
      current.copyWith(
        enable: existing == null ? true : current.enable,
        rule: nextRule,
      ),
    );
  }

  Future<void> _handleDelete(WidgetRef ref) async {
    final confirmed = await _confirmDeleteRules(context);
    if (!confirmed || !mounted) {
      return;
    }
    final selectedRules = ref.read(
      profileOverrideStateProvider.select((state) => state.selectedRules),
    );
    final current = ref.read(
      profileOverrideStateProvider.select((state) => state.overrideData),
    );
    if (current == null) return;
    final nextRule = current.rule.updateRules(
      (rules) => List<Rule>.from(
        rules.where((item) => !selectedRules.contains(item.id)),
      ),
    );
    ref.read(profileOverrideStateProvider.notifier).updateState(
          (state) => state.copyWith(selectedRules: {}),
        );
    _commitProfileOverride(ref, current.copyWith(rule: nextRule));
  }

  Consumer _buildContent() => Consumer(
        builder: (_, ref, child) {
          final isInit = ref.watch(
            profileOverrideStateProvider.select(
              (state) => state.snippet != null && state.overrideData != null,
            ),
          );
          if (!isInit) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          return FadeBox(child: child!);
        },
        child: LayoutBuilder(
          builder: (_, constraints) {
            _currentMaxWidth =
                (constraints.maxWidth - 104).clamp(120.0, double.infinity);
            return CommonAutoHiddenScrollBar(
              controller: _controller,
              child: CustomScrollView(
                controller: _controller,
                slivers: [
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 8),
                  ),
                  SliverToBoxAdapter(
                    child: Consumer(
                      builder: (_, ref, child) {
                        final scriptMode = ref.watch(
                          scriptStateProvider
                              .select((state) => state.realId != null),
                        );
                        if (!scriptMode) {
                          return const SizedBox();
                        }
                        return child!;
                      },
                      child: ListItem(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 0,
                        ),
                        title: Row(
                          spacing: 8,
                          children: [
                            const Icon(Icons.info),
                            Text(appLocalizations.overrideInvalidTip),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 8),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: OverrideSwitch(
                        onChangedCommit: _commitProfileOverride,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: RuleTitle(
                        profileId: widget.profileId,
                        onCommit: _commitProfileOverride,
                        onAddRule: _handleAddOrEdit,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 0,
                    ),
                    sliver: RuleContent(
                      maxWidth: _currentMaxWidth,
                      onCommit: _commitProfileOverride,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 16),
                  ),
                ],
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => ProviderScope(
        overrides: [
          profileOverrideStateProvider.overrideWith(ProfileOverrideState.new),
        ],
        child: Consumer(
          builder: (_, ref, child) {
            _initState(ref);
            return child!;
          },
          child: Consumer(
            builder: (_, ref, ___) {
              final editCount = ref.watch(
                profileOverrideStateProvider.select(
                  (state) => state.selectedRules.length,
                ),
              );
              final isEdit = editCount != 0;
              return CommonScaffold(
                disableBackground: true,
                title: appLocalizations.override,
                body: _buildContent(),
                actions: [
                  if (editCount == 1)
                    IconButton(
                      onPressed: () {
                        final rules = ref.read(
                              profileOverrideStateProvider.select(
                                (state) => state.overrideData?.rule.rules,
                              ),
                            ) ??
                            const <Rule>[];
                        final selectedId = ref
                            .read(profileOverrideStateProvider)
                            .selectedRules
                            .first;
                        final idx =
                            rules.indexWhere((item) => item.id == selectedId);
                        if (idx == -1) return;
                        unawaited(_handleAddOrEdit(ref, rules[idx]));
                      },
                      icon: const Icon(Icons.edit),
                    ),
                  if (editCount > 0)
                    IconButton(
                      onPressed: () {
                        unawaited(_handleDelete(ref));
                      },
                      icon: const Icon(Icons.delete),
                    ),
                ],
                appBarEditState: AppBarEditState(
                  isEdit: isEdit,
                  editCount: editCount,
                  onExit: () {
                    ref.read(profileOverrideStateProvider.notifier).updateState(
                          (state) => state.copyWith(selectedRules: {}),
                        );
                  },
                ),
              );
            },
          ),
        ),
      );
}

class OverrideSwitch extends ConsumerWidget {
  const OverrideSwitch({
    super.key,
    required this.onChangedCommit,
  });

  final void Function(WidgetRef ref, OverrideData next) onChangedCommit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrideData = ref.watch(
      profileOverrideStateProvider.select((state) => state.overrideData),
    );
    return CommonCard(
      onPressed: () {},
      type: CommonCardType.filled,
      radius: 18,
      child: ListItem.switchItem(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(appLocalizations.enableOverride),
        subtitle: Text(appLocalizations.overrideAutoSavedHint),
        delegate: SwitchDelegate(
          value: overrideData?.enable ?? false,
          onChanged: (value) {
            final base = overrideData ?? const OverrideData();
            onChangedCommit(ref, base.copyWith(enable: value));
          },
        ),
      ),
    );
  }
}

class _OverrideRuleHeaderBar extends StatelessWidget {
  const _OverrideRuleHeaderBar({
    required this.subTitle,
    required this.isEdit,
    required this.isSelectAll,
    required this.showTypeToggle,
    required this.isOverrideRule,
    required this.onToggleType,
    required this.onAdd,
    required this.onToggleSelectAll,
  });

  final String subTitle;
  final bool isEdit;
  final bool isSelectAll;
  final bool showTypeToggle;
  final bool isOverrideRule;
  final VoidCallback? onToggleType;
  final VoidCallback onAdd;
  final VoidCallback onToggleSelectAll;

  @override
  Widget build(BuildContext context) => FilledButtonTheme(
        data: const FilledButtonThemeData(
          style: ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ),
        child: IconButtonTheme(
          data: const IconButtonThemeData(
            style: ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              visualDensity: VisualDensity.compact,
              iconSize: WidgetStatePropertyAll(20),
            ),
          ),
          child: ListHeader(
            title: appLocalizations.rule,
            subTitle: subTitle,
            space: 8,
            actions: [
              if (!isEdit && showTypeToggle && onToggleType != null)
                IconButton.filledTonal(
                  icon: Icon(
                    isOverrideRule ? Icons.edit_document : Icons.note_add,
                  ),
                  onPressed: onToggleType,
                ),
              if (!isEdit)
                FilledButton.tonal(
                  key: const ValueKey('override-add-rule-button'),
                  onPressed: onAdd,
                  child: Text(appLocalizations.add),
                )
              else if (isSelectAll)
                FilledButton(
                  onPressed: onToggleSelectAll,
                  child: Text(appLocalizations.selectAll),
                )
              else
                FilledButton.tonal(
                  onPressed: onToggleSelectAll,
                  child: Text(appLocalizations.selectAll),
                ),
            ],
          ),
        ),
      );
}

class RuleTitle extends ConsumerWidget {
  const RuleTitle({
    super.key,
    required this.profileId,
    required this.onCommit,
    required this.onAddRule,
  });

  final String profileId;
  final void Function(WidgetRef ref, OverrideData next) onCommit;
  final Future<void> Function(WidgetRef ref, [Rule? existing]) onAddRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm3 = ref.watch(
      profileOverrideStateProvider.select(
        (state) {
          final overrideRule = state.overrideData?.rule;
          final allIds = overrideRule?.rules.map((item) => item.id).toSet() ??
              const <String>{};
          return VM3(
            a: state.selectedRules.isNotEmpty,
            b: allIds.isNotEmpty && state.selectedRules.containsAll(allIds),
            c: overrideRule?.type == OverrideRuleType.override,
          );
        },
      ),
    );
    final isEdit = vm3.a;
    final isSelectAll = vm3.b;
    final isOverrideRule = vm3.c;

    return _OverrideRuleHeaderBar(
      subTitle: isOverrideRule
          ? appLocalizations.overrideOriginRules
          : appLocalizations.addedOriginRules,
      isEdit: isEdit,
      isSelectAll: isSelectAll,
      showTypeToggle: true,
      isOverrideRule: isOverrideRule,
      onToggleType: () {
        final current = ref.read(
          profileOverrideStateProvider.select((state) => state.overrideData),
        );
        if (current == null) return;
        onCommit(
          ref,
          current.copyWith.rule(
            type: isOverrideRule
                ? OverrideRuleType.added
                : OverrideRuleType.override,
          ),
        );
      },
      onAdd: () => unawaited(onAddRule(ref)),
      onToggleSelectAll: () {
        ref.read(profileOverrideStateProvider.notifier).updateState(
              (state) => state.copyWith(
                selectedRules: isSelectAll
                    ? {}
                    : (state.overrideData?.rule.rules
                            .map((item) => item.id)
                            .toSet() ??
                        {}),
              ),
            );
      },
    );
  }
}

class _ReorderableRuleSliver extends StatelessWidget {
  const _ReorderableRuleSliver({
    required this.rules,
    required this.selectedRules,
    required this.maxWidth,
    required this.cacheTag,
    required this.emptyType,
    required this.onTapRule,
    required this.onReorderRules,
    this.onGetOriginRules,
  });

  final List<Rule> rules;
  final Set<String> selectedRules;
  final double maxWidth;
  final CacheTag cacheTag;
  final OverrideRuleType emptyType;
  final ValueChanged<String> onTapRule;
  final ValueChanged<List<Rule>> onReorderRules;
  final VoidCallback? onGetOriginRules;

  Widget _buildItem({
    required Rule rule,
    required bool isSelected,
    required VoidCallback onTab,
    required BuildContext context,
  }) =>
      Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: CommonCard(
            padding: EdgeInsets.zero,
            radius: 18,
            type: CommonCardType.filled,
            isSelected: isSelected,
            onPressed: onTab,
            child: ListTile(
              minTileHeight: 0,
              minVerticalPadding: 0,
              titleTextStyle: context.textTheme.bodyMedium?.toJetBrainsMono,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              trailing: SizedBox(
                width: 24,
                height: 24,
                child: CommonCheckBox(
                  value: isSelected,
                  isCircle: true,
                  onChanged: (_) => onTab(),
                ),
              ),
              title: Text(rule.value),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 260,
          child: Center(
            child: emptyType == OverrideRuleType.added ||
                    onGetOriginRules == null
                ? Text(appLocalizations.noData)
                : FilledButton(
                    onPressed: onGetOriginRules,
                    child: Text(appLocalizations.getOriginRules),
                  ),
          ),
        ),
      );
    }
    return CacheItemExtentSliverReorderableList(
      tag: cacheTag,
      itemBuilder: (context, index) {
        final rule = rules[index];
        return ReorderableDelayedDragStartListener(
          key: ObjectKey(rule),
          index: index,
          child: _buildItem(
            rule: rule,
            isSelected: selectedRules.contains(rule.id),
            onTab: () => onTapRule(rule.id),
            context: context,
          ),
        );
      },
      proxyDecorator: proxyDecorator,
      itemCount: rules.length,
      onReorder: (oldIndex, newIndex) {
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        final newRules = List<Rule>.from(rules);
        final item = newRules.removeAt(oldIndex);
        newRules.insert(newIndex, item);
        onReorderRules(newRules);
      },
      keyBuilder: (index) => rules[index].id,
      itemExtentBuilder: (index) {
        final rule = rules[index];
        return 40 +
            globalState.measure
                .computeTextSize(
                  Text(
                    rule.value,
                    style: context.textTheme.bodyMedium?.toJetBrainsMono,
                  ),
                  maxWidth: maxWidth,
                )
                .height;
      },
    );
  }
}

class RuleContent extends ConsumerWidget {
  const RuleContent({
    super.key,
    required this.maxWidth,
    required this.onCommit,
  });

  final double maxWidth;
  final void Function(WidgetRef ref, OverrideData next) onCommit;

  void _handleSelect(WidgetRef ref, String ruleId) {
    ref.read(profileOverrideStateProvider.notifier).updateState(
      (state) {
        final newSelectedRules = Set<String>.from(state.selectedRules);
        if (newSelectedRules.contains(ruleId)) {
          newSelectedRules.remove(ruleId);
        } else {
          newSelectedRules.add(ruleId);
        }
        return state.copyWith(selectedRules: newSelectedRules);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm3 = ref.watch(
      profileOverrideStateProvider.select(
        (state) {
          final overrideRule = state.overrideData?.rule;
          return VM3(
            a: overrideRule?.rules ?? const <Rule>[],
            b: overrideRule?.type ?? OverrideRuleType.added,
            c: state.selectedRules,
          );
        },
      ),
    );
    return _ReorderableRuleSliver(
      rules: vm3.a,
      selectedRules: vm3.c,
      maxWidth: maxWidth,
      cacheTag: CacheTag.rules,
      emptyType: vm3.b,
      onTapRule: (id) => _handleSelect(ref, id),
      onReorderRules: (newRules) {
        final current = ref.read(
          profileOverrideStateProvider.select((state) => state.overrideData),
        );
        if (current == null) return;
        onCommit(
          ref,
          current.copyWith(
            rule: current.rule.updateRules((_) => newRules),
          ),
        );
      },
      onGetOriginRules: () {
        final originRules = ref.read(
          profileOverrideStateProvider.select(
            (state) => state.snippet?.rule ?? const <Rule>[],
          ),
        );
        final current = ref.read(
          profileOverrideStateProvider.select((state) => state.overrideData),
        );
        if (current == null) return;
        onCommit(
          ref,
          current.copyWith.rule(overrideRules: originRules),
        );
      },
    );
  }
}

class AddRuleDialog extends StatefulWidget {
  const AddRuleDialog({
    super.key,
    required this.snippet,
    this.rule,
    this.isGlobal = false,
  });

  final ClashConfigSnippet snippet;
  final Rule? rule;
  final bool isGlobal;

  @override
  State<AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<AddRuleDialog> {
  late RuleAction _ruleAction;
  String? _selectedTargetValue;
  final _contentController = TextEditingController();
  final _ruleProviderController = TextEditingController();
  final _subRuleController = TextEditingController();
  bool _noResolve = false;
  bool _src = false;
  List<DropdownMenuEntry<String>> _targetItems = [];
  List<DropdownMenuEntry<String>> _ruleProviderItems = [];
  List<DropdownMenuEntry<String>> _subRuleItems = [];
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _initState();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _ruleProviderController.dispose();
    _subRuleController.dispose();
    super.dispose();
  }

  void _initState() {
    final seenTargets = <String>{};
    final builtTargets = <DropdownMenuEntry<String>>[];
    void addTarget(String value, String label) {
      if (value.isEmpty || !seenTargets.add(value)) return;
      builtTargets.add(DropdownMenuEntry<String>(value: value, label: label));
    }

    if (widget.isGlobal) {
      addTarget(
        semanticDefaultProxyTarget,
        appLocalizations.defaultProxyAutoTarget,
      );
      for (final builtin in RuleTarget.values) {
        addTarget(builtin.name, builtin.name);
      }
      for (final group in widget.snippet.proxyGroups) {
        addTarget(group.name, group.name);
      }
    } else {
      for (final group in widget.snippet.proxyGroups) {
        addTarget(group.name, group.name);
      }
      addTarget(
        semanticDefaultProxyTarget,
        appLocalizations.defaultProxyAutoTarget,
      );
      for (final builtin in RuleTarget.values) {
        addTarget(builtin.name, builtin.name);
      }
    }

    _ruleProviderItems = [
      for (final item in widget.snippet.ruleProvider)
        DropdownMenuEntry(value: item.name, label: item.name),
    ];
    _subRuleItems = [
      for (final item in widget.snippet.subRules)
        DropdownMenuEntry(value: item.name, label: item.name),
    ];

    if (widget.rule != null) {
      final parsedRule = ParsedRule.parseString(widget.rule!.value);
      _ruleAction = parsedRule.ruleAction;
      _contentController.text = parsedRule.content ?? '';
      final existingTarget = parsedRule.ruleTarget;
      if (existingTarget != null && existingTarget.isNotEmpty) {
        addTarget(existingTarget, existingTarget);
      }
      _targetItems = builtTargets;
      _selectedTargetValue = existingTarget;
      _ruleProviderController.text = parsedRule.ruleProvider ?? '';
      _subRuleController.text = parsedRule.subRule ?? '';
      _noResolve = parsedRule.noResolve;
      _src = parsedRule.src;
      return;
    }

    _targetItems = builtTargets;
    _ruleAction = RuleAction.DOMAIN_SUFFIX;
    if (_targetItems.isNotEmpty) {
      _selectedTargetValue = _targetItems.first.value;
    }
    if (_ruleProviderItems.isNotEmpty) {
      _ruleProviderController.text = _ruleProviderItems.first.value;
    }
    if (_subRuleItems.isNotEmpty) {
      _subRuleController.text = _subRuleItems.first.value;
    }
  }

  @override
  void didUpdateWidget(AddRuleDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rule != widget.rule ||
        oldWidget.isGlobal != widget.isGlobal) {
      _initState();
    }
  }

  void _handleSubmit() {
    final res = _formKey.currentState?.validate();
    if (res == false) {
      return;
    }
    final parsedRule = ParsedRule(
      ruleAction: _ruleAction,
      content: _contentController.text.trim(),
      ruleProvider: _ruleProviderController.text.trim(),
      ruleTarget: _selectedTargetValue,
      subRule: _subRuleController.text.trim(),
      noResolve: _noResolve,
      src: _src,
    );
    final rule = widget.rule != null
        ? widget.rule!.copyWith(value: parsedRule.value)
        : Rule.value(parsedRule.value);
    Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) => CommonDialog(
        title: appLocalizations.addRule,
        actions: [
          TextButton(
            key: const ValueKey('add-rule-confirm-button'),
            onPressed: _handleSubmit,
            child: Text(appLocalizations.confirm),
          ),
        ],
        child: DropdownMenuTheme(
          data: DropdownMenuThemeData(
            inputDecorationTheme: InputDecorationTheme(
              border: const OutlineInputBorder(),
              labelStyle: context.textTheme.bodyLarge
                  ?.copyWith(overflow: TextOverflow.ellipsis),
            ),
          ),
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (_, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonal(
                    key: const ValueKey('add-rule-action-button'),
                    onPressed: () async {
                      _ruleAction = await _showRuleDialog<RuleAction>(
                            context,
                            OptionsDialog<RuleAction>(
                              title: appLocalizations.ruleName,
                              options: RuleAction.values,
                              textBuilder: (item) => item.value,
                              value: _ruleAction,
                            ),
                          ) ??
                          _ruleAction;
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    child: Text(_ruleAction.value),
                  ),
                  const SizedBox(height: 24),
                  if (_ruleAction == RuleAction.RULE_SET) ...[
                    FormField(
                      validator: (_) {
                        if (_ruleProviderController.text.isEmpty) {
                          return appLocalizations
                              .emptyTip(appLocalizations.ruleProviders);
                        }
                        return null;
                      },
                      builder: (field) => DropdownMenu(
                        expandedInsets: EdgeInsets.zero,
                        controller: _ruleProviderController,
                        label: Text(appLocalizations.ruleProviders),
                        menuHeight: 250,
                        errorText: field.errorText,
                        dropdownMenuEntries: _ruleProviderItems,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ] else if (_ruleAction != RuleAction.MATCH) ...[
                    TextFormField(
                      key: const ValueKey('add-rule-content-field'),
                      controller: _contentController,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: appLocalizations.content,
                      ),
                      validator: (_) {
                        if (_contentController.text.trim().isEmpty) {
                          return appLocalizations
                              .emptyTip(appLocalizations.content);
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                  _ruleAction == RuleAction.SUB_RULE
                      ? FormField(
                          validator: (_) {
                            if (_subRuleController.text.isEmpty) {
                              return appLocalizations
                                  .emptyTip(appLocalizations.subRule);
                            }
                            return null;
                          },
                          builder: (field) => DropdownMenu(
                            width: 220,
                            enableFilter: false,
                            enableSearch: false,
                            controller: _subRuleController,
                            label: Text(appLocalizations.subRule),
                            menuHeight: 250,
                            dropdownMenuEntries: _subRuleItems,
                            errorText: field.errorText,
                          ),
                        )
                      : FormField<String>(
                          validator: (_) {
                            if ((_selectedTargetValue ?? '').isEmpty) {
                              return appLocalizations.emptyTip(
                                appLocalizations.ruleTarget,
                              );
                            }
                            return null;
                          },
                          builder: (field) => DropdownMenu<String>(
                            initialSelection: _selectedTargetValue,
                            label: Text(appLocalizations.ruleTarget),
                            width: 240,
                            menuHeight: 250,
                            enableFilter: false,
                            enableSearch: false,
                            dropdownMenuEntries: _targetItems,
                            errorText: field.errorText,
                            onSelected: (value) {
                              setState(() {
                                _selectedTargetValue = value;
                              });
                            },
                          ),
                        ),
                  if (_ruleAction.hasParams) ...[
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      children: [
                        CommonCard(
                          radius: 8,
                          isSelected: _src,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Text(
                              appLocalizations.sourceIp,
                              style: context.textTheme.bodyMedium,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _src = !_src;
                            });
                          },
                        ),
                        CommonCard(
                          radius: 8,
                          isSelected: _noResolve,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Text(
                              appLocalizations.noResolve,
                              style: context.textTheme.bodyMedium,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _noResolve = !_noResolve;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      );
}
