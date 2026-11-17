// ignore_for_file: deprecated_member_use

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ThemeView extends StatelessWidget {
  const ThemeView({super.key});

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        child: Column(
          spacing: 24,
          children: [
            _DayNightSkyConsoleCard(),
            _SkyAtmosphereCard(),
            _PrimaryColorItem(),
            _TextScaleFactorItem(),
            SizedBox(
              height: 64,
            ),
          ],
        ),
      );
}

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.info,
    required this.child,
    this.actions = const [],
  });

  final Widget child;
  final Info info;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Wrap(
        runSpacing: 16,
        children: [
          InfoHeader(
            info: info,
            actions: actions,
          ),
          child,
        ],
      );
}

class _DayNightSkyConsoleCard extends ConsumerWidget {
  const _DayNightSkyConsoleCard();

  String _statusLabel(
    DayNightSkyMode mode,
    DayNightSkyPhase phase,
  ) =>
      switch (mode) {
        DayNightSkyMode.alwaysNight => appLocalizations.themeSkyStatusLockedNight,
        DayNightSkyMode.alwaysDay => appLocalizations.themeSkyStatusLockedDay,
        DayNightSkyMode.followConnection => switch (phase) {
            DayNightSkyPhase.day => appLocalizations.themeSkyStatusDayConnected,
            DayNightSkyPhase.connecting =>
              appLocalizations.themeSkyStatusConnecting,
            DayNightSkyPhase.night =>
              appLocalizations.themeSkyStatusNightDisconnected,
          },
      };

  Color _statusDotColor(DayNightSkyPhase phase) => switch (phase) {
        DayNightSkyPhase.day => const Color(0xFF34D399),
        DayNightSkyPhase.connecting => const Color(0xFFFBBF24),
        DayNightSkyPhase.night => const Color(0xFF60A5FA),
      };

  String _modeDescription(DayNightSkyMode mode) => switch (mode) {
        DayNightSkyMode.followConnection =>
          appLocalizations.themeSkyModeFollowDesc,
        DayNightSkyMode.alwaysNight => appLocalizations.themeSkyModeNightDesc,
        DayNightSkyMode.alwaysDay => appLocalizations.themeSkyModeDayDesc,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (skyMode, skyAmbientAnimation, ignoreCustomBackground) = ref.watch(
      themeSettingProvider.select(
        (state) => (
          state.skyMode,
          state.skyAmbientAnimation,
          state.ignoreCustomBackground,
        ),
      ),
    );
    final isRunning =
        ref.watch(runTimeProvider.select((state) => state != null));
    final pendingTarget = ref.watch(statusSwitchPendingProvider);
    final backgroundUrl = ref.watch(backgroundUrlProvider);
    final hasCustomBackground =
        backgroundUrl != null && backgroundUrl.isNotEmpty;
    final useCustomBackground = hasCustomBackground && !ignoreCustomBackground;

    final previewPhase = resolveDayNightSkyPhase(
      isRunning: isRunning,
      pendingTarget: pendingTarget,
      mode: skyMode,
    );
    final statusText = useCustomBackground
        ? appLocalizations.themeSkyStatusCustomBgActive
        : _statusLabel(skyMode, previewPhase);
    final dotColor = _statusDotColor(previewPhase);
    final colorScheme = context.colorScheme;
    final hairline = freedomNetHairlineColor(colorScheme);

    final modeOptions = <({
      DayNightSkyMode mode,
      IconData icon,
      String label,
      Key key,
    })>[
      (
        mode: DayNightSkyMode.followConnection,
        icon: Icons.auto_awesome_rounded,
        label: appLocalizations.themeSkyModeFollow,
        key: const ValueKey('theme-sky-mode-followConnection'),
      ),
      (
        mode: DayNightSkyMode.alwaysNight,
        icon: Icons.nights_stay_rounded,
        label: appLocalizations.themeSkyModeNight,
        key: const ValueKey('theme-sky-mode-alwaysNight'),
      ),
      (
        mode: DayNightSkyMode.alwaysDay,
        icon: Icons.wb_sunny_rounded,
        label: appLocalizations.themeSkyModeDay,
        key: const ValueKey('theme-sky-mode-alwaysDay'),
      ),
    ];

    return ItemCard(
      info: Info(
        label: appLocalizations.themeSkyConsoleSection,
        iconData: Icons.contrast_rounded,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('theme-sky-live-preview-card'),
              height: 84,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DayNightSkyBackground(
                      phase: previewPhase,
                      ambientAnimation: skyAmbientAnimation,
                      includeInDebugSnapshot: false,
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xB80B1324),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: dotColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      statusText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.textTheme.labelMedium
                                          ?.copyWith(
                                        color: const Color(0xFFF8FAFC),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasCustomBackground) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.wallpaper_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appLocalizations.themeCustomBgNotice,
                            style: context.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            appLocalizations.themeIgnoreCustomBgLabel,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      key: const ValueKey('theme-ignore-custom-bg-switch'),
                      value: ignoreCustomBackground,
                      onChanged: (value) {
                        ref.read(themeSettingProvider.notifier).updateState(
                              (state) => state.copyWith(
                                ignoreCustomBackground: value,
                              ),
                            );
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                for (final item in modeOptions)
                  Expanded(
                    child: _SkyModeOptionCard(
                      key: item.key,
                      icon: item.icon,
                      label: item.label,
                      selected: skyMode == item.mode,
                      onTap: () {
                        ref.read(themeSettingProvider.notifier).updateState(
                              (state) => state.copyWith(skyMode: item.mode),
                            );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _modeDescription(skyMode),
              style: context.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkyModeOptionCard extends StatelessWidget {
  const _SkyModeOptionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final hairline = freedomNetHairlineColor(colorScheme);
    final bg = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.72)
        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.56);
    final borderColor =
        selected ? colorScheme.primary.withValues(alpha: 0.75) : hairline;
    final fg =
        selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: borderColor,
                width: selected ? 1.4 : 1.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? colorScheme.primary : fg,
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkyAtmosphereCard extends ConsumerWidget {
  const _SkyAtmosphereCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (glassPreset, skyAmbientAnimation, ignoreCustomBackground) = ref.watch(
      themeSettingProvider.select(
        (state) => (
          state.glassPreset,
          state.skyAmbientAnimation,
          state.ignoreCustomBackground,
        ),
      ),
    );
    final backgroundUrl = ref.watch(backgroundUrlProvider);
    final useCustomBackground = backgroundUrl != null &&
        backgroundUrl.isNotEmpty &&
        !ignoreCustomBackground;
    final colorScheme = context.colorScheme;
    final hairline = freedomNetHairlineColor(colorScheme);

    final presets = <({
      DayNightGlassPreset preset,
      String label,
      Key key,
    })>[
      (
        preset: DayNightGlassPreset.airy,
        label: appLocalizations.themeGlassPresetAiry,
        key: const ValueKey('theme-glass-preset-airy'),
      ),
      (
        preset: DayNightGlassPreset.balanced,
        label: appLocalizations.themeGlassPresetBalanced,
        key: const ValueKey('theme-glass-preset-balanced'),
      ),
      (
        preset: DayNightGlassPreset.solid,
        label: appLocalizations.themeGlassPresetSolid,
        key: const ValueKey('theme-glass-preset-solid'),
      ),
    ];

    return ItemCard(
      info: Info(
        label: appLocalizations.themeAtmosphereSection,
        iconData: Icons.blur_on_rounded,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (useCustomBackground) ...[
              Container(
                key: const ValueKey('theme-atmosphere-custom-bg-hint'),
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: hairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appLocalizations.themeAtmosphereCustomBgHint,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            IgnorePointer(
              ignoring: useCustomBackground,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: useCustomBackground ? 0.45 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      appLocalizations.themeGlassPresetLabel,
                      style: context.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh
                            .withValues(alpha: 0.56),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: hairline),
                      ),
                      child: Row(
                        spacing: 4,
                        children: [
                          for (final item in presets)
                            Expanded(
                              child: Semantics(
                                key: item.key,
                                container: true,
                                button: true,
                                selected: glassPreset == item.preset,
                                enabled: !useCustomBackground,
                                label: item.label,
                                excludeSemantics: true,
                                onTap: useCustomBackground
                                    ? null
                                    : () {
                                        ref
                                            .read(themeSettingProvider.notifier)
                                            .updateState(
                                              (state) => state.copyWith(
                                                glassPreset: item.preset,
                                              ),
                                            );
                                      },
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(9),
                                    onTap: useCustomBackground
                                        ? null
                                        : () {
                                            ref
                                                .read(themeSettingProvider
                                                    .notifier)
                                                .updateState(
                                                  (state) => state.copyWith(
                                                    glassPreset: item.preset,
                                                  ),
                                                );
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: glassPreset == item.preset
                                            ? colorScheme.primaryContainer
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        item.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.textTheme.labelMedium
                                            ?.copyWith(
                                          color: glassPreset == item.preset
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurfaceVariant,
                                          fontWeight: glassPreset == item.preset
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          Icons.air_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appLocalizations.themeSkyAmbientAnimation,
                                style: context.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                appLocalizations.themeSkyAmbientAnimationDesc,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          key: const ValueKey(
                              'theme-sky-ambient-animation-switch'),
                          value: skyAmbientAnimation,
                          onChanged: useCustomBackground
                              ? null
                              : (value) {
                                  ref
                                      .read(themeSettingProvider.notifier)
                                      .updateState(
                                        (state) => state.copyWith(
                                          skyAmbientAnimation: value,
                                        ),
                                      );
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryColorItem extends ConsumerStatefulWidget {
  const _PrimaryColorItem();

  @override
  ConsumerState<_PrimaryColorItem> createState() => _PrimaryColorItemState();
}

class _PrimaryColorItemState extends ConsumerState<_PrimaryColorItem> {
  int? _removablePrimaryColor;

  int _calcColumns(double maxWidth) => max((maxWidth / 96).ceil(), 3);

  Future<void> _handleReset() async {
    final res = await globalState.showMessage(
      message: TextSpan(
        text: appLocalizations.resetTip,
      ),
    );
    if (res != true) {
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            primaryColors: defaultPrimaryColors,
            primaryColor: defaultPrimaryColor,
            schemeVariant: defaultThemeProps.schemeVariant,
          ),
        );
  }

  Future<void> _handleDel() async {
    if (_removablePrimaryColor == null) {
      return;
    }
    final res = await globalState.showMessage(
      message: TextSpan(
        text: appLocalizations.deleteTip(
          appLocalizations.colorSchemes,
        ),
      ),
    );
    if (res != true) {
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
      (state) {
        final newPrimaryColors = List<int>.from(state.primaryColors)
          ..remove(_removablePrimaryColor);
        var newPrimaryColor = state.primaryColor;
        if (state.primaryColor == _removablePrimaryColor) {
          if (newPrimaryColors.contains(defaultPrimaryColor)) {
            newPrimaryColor = defaultPrimaryColor;
          } else {
            newPrimaryColor = null;
          }
        }
        return state.copyWith(
          primaryColors: newPrimaryColors,
          primaryColor: newPrimaryColor,
        );
      },
    );
    setState(() {
      _removablePrimaryColor = null;
    });
  }

  Future<void> _handleAdd() async {
    final res = await globalState.showCommonDialog<int>(
      child: const _PaletteDialog(),
    );
    if (res == null) {
      return;
    }
    final isExists = ref.read(
      themeSettingProvider.select((state) => state.primaryColors.contains(res)),
    );
    if (isExists && mounted) {
      context.showNotifier(
        appLocalizations.existsTip(
          appLocalizations.colorSchemes,
        ),
      );
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            primaryColors: List.from(
              state.primaryColors,
            )..add(res),
          ),
        );
  }

  Future<void> _handleChangeSchemeVariant() async {
    final schemeVariant = ref.read(
      themeSettingProvider.select(
        (state) => state.schemeVariant,
      ),
    );
    final value = await globalState.showCommonDialog<DynamicSchemeVariant>(
      child: OptionsDialog<DynamicSchemeVariant>(
        title: appLocalizations.colorSchemes,
        options: DynamicSchemeVariant.values,
        textBuilder: (item) => Intl.message("${item.name}Scheme"),
        value: schemeVariant,
      ),
    );
    if (value == null) {
      return;
    }
    ref.read(themeSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            schemeVariant: value,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final vm4 = ref.watch(
      themeSettingProvider.select(
        (state) => VM4(
          a: state.primaryColor,
          b: state.primaryColors,
          c: state.schemeVariant,
          d: state.primaryColor == defaultPrimaryColor &&
              state.schemeVariant == defaultThemeProps.schemeVariant &&
              intListEquality.equals(state.primaryColors, defaultPrimaryColors),
        ),
      ),
    );
    final primaryColor = vm4.a;
    final primaryColors = [null, ...vm4.b];
    final schemeVariant = vm4.c;
    final isEquals = vm4.d;

    return CommonPopScope(
      onPop: () {
        if (_removablePrimaryColor != null) {
          setState(() {
            _removablePrimaryColor = null;
          });
          return false;
        }
        return true;
      },
      child: ItemCard(
        info: Info(
          label: appLocalizations.themeColor,
          iconData: Icons.palette,
        ),
        actions: genActions(
          [
            if (_removablePrimaryColor == null)
              OutlinedButton.icon(
                key: const ValueKey('theme-scheme-variant-button'),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  side: WidgetStatePropertyAll(
                    BorderSide(
                      color: freedomNetHairlineColor(context.colorScheme),
                    ),
                  ),
                ),
                onPressed: _handleChangeSchemeVariant,
                icon: const Icon(Icons.tune_rounded, size: 15),
                label: Text(
                  Intl.message("${schemeVariant.name}Scheme"),
                  style: context.textTheme.labelMedium,
                ),
              ),
            if (_removablePrimaryColor != null)
              FilledButton(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  setState(() {
                    _removablePrimaryColor = null;
                  });
                },
                child: Text(appLocalizations.cancel),
              ),
            if (_removablePrimaryColor == null && !isEquals)
              IconButton.filledTonal(
                key: const ValueKey('theme-accent-reset-button'),
                tooltip: appLocalizations.reset,
                iconSize: 20,
                padding: const EdgeInsets.all(4),
                visualDensity: VisualDensity.compact,
                onPressed: _handleReset,
                icon: const Icon(Icons.replay),
              )
          ],
          space: 8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final columns = _calcColumns(constraints.maxWidth);
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final color in primaryColors)
                    Container(
                      clipBehavior: Clip.none,
                      width: itemWidth,
                      height: itemWidth,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          EffectGestureDetector(
                            child: ColorSchemeBox(
                              isSelected: color == primaryColor,
                              primaryColor: color != null ? Color(color) : null,
                              onPressed: () {
                                setState(() {
                                  _removablePrimaryColor = null;
                                });
                                ref
                                    .read(themeSettingProvider.notifier)
                                    .updateState(
                                      (state) => state.copyWith(
                                        primaryColor: color,
                                      ),
                                    );
                              },
                            ),
                            onLongPress: () {
                              setState(() {
                                _removablePrimaryColor = color;
                              });
                            },
                          ),
                          if (_removablePrimaryColor != null &&
                              _removablePrimaryColor == color)
                            Container(
                              color: Colors.white.opacity0,
                              padding: const EdgeInsets.all(8),
                              child: IconButton.filledTonal(
                                onPressed: _handleDel,
                                padding: const EdgeInsets.all(12),
                                iconSize: 30,
                                icon: Icon(
                                  color: context.colorScheme.primary,
                                  Icons.delete,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_removablePrimaryColor == null)
                    Container(
                      width: itemWidth,
                      height: itemWidth,
                      padding: const EdgeInsets.all(
                        4,
                      ),
                      child: IconButton.filledTonal(
                        onPressed: _handleAdd,
                        iconSize: 32,
                        icon: Icon(
                          color: context.colorScheme.primary,
                          Icons.add,
                        ),
                      ),
                    )
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TextScaleFactorItem extends ConsumerWidget {
  const _TextScaleFactorItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = ref.watch(
      themeSettingProvider.select(
        (state) => state.textScale,
      ),
    );
    final process = "${((textScale.scale * 100) as double).round()}%";
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.text_fields,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appLocalizations.textScale,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (!textScale.enable) ...[
                      const SizedBox(height: 2),
                      Text(
                        appLocalizations.themeTextScaleDefaultDesc,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                key: const ValueKey('theme-text-scale-switch'),
                value: textScale.enable,
                onChanged: (value) {
                  ref.read(themeSettingProvider.notifier).updateState(
                        (state) => state.copyWith.textScale(
                          enable: value,
                        ),
                      );
                },
              ),
            ],
          ),
          if (textScale.enable) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              spacing: 24,
              children: [
                Expanded(
                  child: SliderTheme(
                    data: _SliderDefaultsM3(context),
                    child: Slider(
                      padding: EdgeInsets.zero,
                      min: minTextScale,
                      max: maxTextScale,
                      value: textScale.scale,
                      onChanged: (value) {
                        ref.read(themeSettingProvider.notifier).updateState(
                              (state) => state.copyWith.textScale(
                                scale: value,
                              ),
                            );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    process,
                    style: context.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PaletteDialog extends StatefulWidget {
  const _PaletteDialog();

  @override
  State<_PaletteDialog> createState() => _PaletteDialogState();
}

class _PaletteDialogState extends State<_PaletteDialog> {
  final _controller = ValueNotifier<ui.Color>(Colors.transparent);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CommonDialog(
        title: appLocalizations.palette,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(appLocalizations.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_controller.value.toARGB32());
            },
            child: Text(appLocalizations.confirm),
          ),
        ],
        child: Column(
          children: [
            const SizedBox(
              height: 8,
            ),
            SizedBox(
              width: 250,
              height: 250,
              child: Palette(
                controller: _controller,
              ),
            ),
            const SizedBox(
              height: 24,
            ),
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (_, color, __) => PrimaryColorBox(
                primaryColor: color,
                child: FilledButton(
                  onPressed: () {},
                  child: Text(
                    _controller.value.hex,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _SliderDefaultsM3 extends SliderThemeData {
  _SliderDefaultsM3(this.context) : super(trackHeight: 16.0);

  final BuildContext context;
  late final ColorScheme _colors = Theme.of(context).colorScheme;

  @override
  Color? get activeTrackColor => _colors.primary;

  @override
  Color? get inactiveTrackColor => _colors.secondaryContainer;

  @override
  Color? get secondaryActiveTrackColor => _colors.primary.withOpacity(0.54);

  @override
  Color? get disabledActiveTrackColor => _colors.onSurface.withOpacity(0.38);

  @override
  Color? get disabledInactiveTrackColor => _colors.onSurface.withOpacity(0.12);

  @override
  Color? get disabledSecondaryActiveTrackColor =>
      _colors.onSurface.withOpacity(0.38);

  @override
  Color? get activeTickMarkColor => _colors.onPrimary.withOpacity(1.0);

  @override
  Color? get inactiveTickMarkColor =>
      _colors.onSecondaryContainer.withOpacity(1.0);

  @override
  Color? get disabledActiveTickMarkColor => _colors.onInverseSurface;

  @override
  Color? get disabledInactiveTickMarkColor => _colors.onSurface;

  @override
  Color? get thumbColor => _colors.primary;

  @override
  Color? get disabledThumbColor => _colors.onSurface.withOpacity(0.38);

  @override
  Color? get overlayColor => WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return _colors.primary.withOpacity(0.1);
        }
        if (states.contains(WidgetState.hovered)) {
          return _colors.primary.withOpacity(0.08);
        }
        if (states.contains(WidgetState.focused)) {
          return _colors.primary.withOpacity(0.1);
        }

        return Colors.transparent;
      });

  @override
  TextStyle? get valueIndicatorTextStyle =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
            color: _colors.onInverseSurface,
          );

  @override
  Color? get valueIndicatorColor => _colors.inverseSurface;

  @override
  SliderComponentShape? get valueIndicatorShape =>
      const RoundedRectSliderValueIndicatorShape();

  @override
  SliderComponentShape? get thumbShape => const HandleThumbShape();

  @override
  SliderTrackShape? get trackShape => const GappedSliderTrackShape();

  @override
  SliderComponentShape? get overlayShape => const RoundSliderOverlayShape();

  @override
  SliderTickMarkShape? get tickMarkShape =>
      const RoundSliderTickMarkShape(tickMarkRadius: 4.0 / 2);

  @override
  WidgetStateProperty<Size?>? get thumbSize =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const Size(4.0, 44.0);
        }
        if (states.contains(WidgetState.hovered)) {
          return const Size(4.0, 44.0);
        }
        if (states.contains(WidgetState.focused)) {
          return const Size(2.0, 44.0);
        }
        if (states.contains(WidgetState.pressed)) {
          return const Size(2.0, 44.0);
        }
        return const Size(4.0, 44.0);
      });

  @override
  double? get trackGap => 6.0;
}
