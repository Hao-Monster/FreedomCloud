import 'package:flclashx/common/app_localizations.dart';
import 'package:flclashx/common/constant.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';

const Color kFreedomNetDarkCanvas = Color(0xFF0B0E14);
const Color kFreedomNetDarkRecessed = Color(0xFF07090E);
const Color kFreedomNetDarkCard = Color(0xFF121722);
const Color kFreedomNetDarkCardHigh = Color(0xFF171E2C);
const Color kFreedomNetDarkTrack = Color(0xFF1E2636);
const Color kFreedomNetDarkPrimary = Color(0xFF38BDF8);

const Color kFreedomNetLightCanvas = Color(0xFFF4F6FA);
const Color kFreedomNetLightRecessed = Color(0xFFE8ECF4);
const Color kFreedomNetLightCard = Color(0xFFFFFFFF);
const Color kFreedomNetLightCardHigh = Color(0xFFF1F5F9);
const Color kFreedomNetLightTrack = Color(0xFFE2E8F0);
const Color kFreedomNetLightPrimary = Color(0xFF0284C7);

const Color kLatencyFastColor = Color(0xFF10B981);
const Color kLatencyMediumColor = Color(0xFFF59E0B);
const Color kLatencyErrorColor = Color(0xFFEF4444);
const int kLatencyFastMaxMs = 2000;

const Color kPortalBrandMarkBg = Color(0xFF71D7A7);
const Color kPortalBrandMarkFg = Color(0xFF102018);
const double kPortalBrandMarkCornerRatio = 10.0 / 34.0;

const List<String> kFreedomNetFontFallback = <String>[
  'Segoe UI Variable Text',
  'Segoe UI',
  'PingFang SC',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'sans-serif',
];

Color freedomNetHairlineColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.065)
        : const Color(0xFF0F172A).withValues(alpha: 0.075);

/// Calibrates [base] onto the Plan A Obsidian Slate (dark) / Porcelain Cloud
/// (light) neutral surface architecture so surfaces never inherit muddy M3
/// seed tints while preserving custom accent swatches when selected.
ColorScheme calibrateFreedomNetColorScheme(
  ColorScheme base, {
  Color? seedColor,
}) {
  final isFlagshipSeed =
      seedColor == null || seedColor.toARGB32() == defaultPrimaryColor;
  if (base.brightness == Brightness.dark) {
    return base.copyWith(
      primary: isFlagshipSeed ? kFreedomNetDarkPrimary : base.primary,
      onPrimary: isFlagshipSeed ? const Color(0xFF04131D) : base.onPrimary,
      primaryContainer:
          isFlagshipSeed ? const Color(0xFF0C2D48) : base.primaryContainer,
      onPrimaryContainer:
          isFlagshipSeed ? const Color(0xFFBAE6FD) : base.onPrimaryContainer,
      secondary: isFlagshipSeed ? const Color(0xFF7DD3FC) : base.secondary,
      onSecondary: isFlagshipSeed ? const Color(0xFF082F49) : base.onSecondary,
      secondaryContainer:
          isFlagshipSeed ? const Color(0xFF0F2942) : base.secondaryContainer,
      onSecondaryContainer:
          isFlagshipSeed ? const Color(0xFFE0F2FE) : base.onSecondaryContainer,
      surface: kFreedomNetDarkCanvas,
      surfaceDim: kFreedomNetDarkRecessed,
      surfaceBright: const Color(0xFF1F2737),
      surfaceContainerLowest: kFreedomNetDarkRecessed,
      surfaceContainerLow: const Color(0xFF0F131C),
      surfaceContainer: kFreedomNetDarkCard,
      surfaceContainerHigh: kFreedomNetDarkCardHigh,
      surfaceContainerHighest: kFreedomNetDarkTrack,
      onSurface: const Color(0xFFF1F5F9),
      onSurfaceVariant: const Color(0xFF94A3B8),
      outline: const Color(0xFF334155),
      outlineVariant: const Color(0xFF1E293B),
      surfaceTint: Colors.transparent,
    );
  }
  return base.copyWith(
    primary: isFlagshipSeed ? kFreedomNetLightPrimary : base.primary,
    onPrimary: isFlagshipSeed ? Colors.white : base.onPrimary,
    primaryContainer:
        isFlagshipSeed ? const Color(0xFFE0F2FE) : base.primaryContainer,
    onPrimaryContainer:
        isFlagshipSeed ? const Color(0xFF075985) : base.onPrimaryContainer,
    secondary: isFlagshipSeed ? const Color(0xFF0369A1) : base.secondary,
    onSecondary: isFlagshipSeed ? Colors.white : base.onSecondary,
    secondaryContainer:
        isFlagshipSeed ? const Color(0xFFE0F2FE) : base.secondaryContainer,
    onSecondaryContainer:
        isFlagshipSeed ? const Color(0xFF0C4A6E) : base.onSecondaryContainer,
    surface: kFreedomNetLightCanvas,
    surfaceDim: kFreedomNetLightRecessed,
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF8FAFC),
    surfaceContainer: kFreedomNetLightCard,
    surfaceContainerHigh: kFreedomNetLightCardHigh,
    surfaceContainerHighest: kFreedomNetLightTrack,
    onSurface: const Color(0xFF0F172A),
    onSurfaceVariant: const Color(0xFF475569),
    outline: const Color(0xFFCBD5E1),
    outlineVariant: const Color(0xFFE2E8F0),
    surfaceTint: Colors.transparent,
  );
}

ThemeData buildFreedomNetThemeData({
  required ColorScheme colorScheme,
  PageTransitionsTheme? pageTransitionsTheme,
}) {
  final isDark = colorScheme.brightness == Brightness.dark;
  final hairline = freedomNetHairlineColor(colorScheme);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    pageTransitionsTheme: pageTransitionsTheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    fontFamilyFallback: kFreedomNetFontFallback,
  );
  final textTheme = base.textTheme.apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
    fontFamilyFallback: kFreedomNetFontFallback,
  );

  return base.copyWith(
    textTheme: textTheme,
    dividerColor: hairline,
    dividerTheme: DividerThemeData(
      color: hairline,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: colorScheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: hairline),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      elevation: 0,
      pressElevation: 0,
      side: BorderSide.none,
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedColor: colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
      secondarySelectedColor:
          colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
      checkmarkColor: colorScheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
      ),
      labelStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: hairline),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(
          color: colorScheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.14),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: hairline)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
  );
}

/// Portal F brand emblem (`<span class="portal-brand-mark">F</span>`) for 自由云 / FreedomNet.
class FreedomNetBrandMark extends StatelessWidget {
  const FreedomNetBrandMark({
    super.key,
    this.size = 36,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * kPortalBrandMarkCornerRatio;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kPortalBrandMarkBg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: kPortalBrandMarkFg.withValues(alpha: 0.10),
            blurRadius: size * 0.16,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: const CustomPaint(
        painter: _FreedomNetGlyphPainter(),
      ),
    );
  }
}

class _FreedomNetGlyphPainter extends CustomPainter {
  const _FreedomNetGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hF = h * 0.43;
    final wF = hF * 0.58;
    final stem = hF * 0.195;
    final left = (w - wF) / 2.0 + w * 0.015;
    final top = (h - hF) / 2.0;
    final corner = Radius.circular(stem * 0.12);

    final stemPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, stem, hF),
        corner,
      ));
    final topBarPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, wF, stem),
        corner,
      ));
    final midBarPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top + hF * 0.42, wF * 0.86, stem),
        corner,
      ));

    final fPath = Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, stemPath, topBarPath),
      midBarPath,
    );

    final paint = Paint()
      ..color = kPortalBrandMarkFg
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(fPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Solemn open-source heritage & engineering credit cards displayed in
/// Settings -> About (`AboutView`).
class FreedomNetTributeCards extends StatelessWidget {
  const FreedomNetTributeCards({
    super.key,
    this.flclashxCardKey,
    this.geminiCardKey,
  });

  final Key? flclashxCardKey;
  final Key? geminiCardKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = colors.brightness == Brightness.dark;
    final hairline = freedomNetHairlineColor(colors);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Solemn Open-Source Tribute to FlClashX
        Container(
          key: flclashxCardKey,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary.withValues(alpha: isDark ? 0.11 : 0.07),
                colors.surfaceContainer,
              ],
            ),
            border: Border.all(
              color: colors.primary.withValues(alpha: isDark ? 0.28 : 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          colors.primary.withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_rounded,
                          size: 13,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            appLocalizations.tributeFlclashxBadge,
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                appLocalizations.tributeFlclashxTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appLocalizations.tributeFlclashxBody,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TributeRepoChip(
                    label: 'FlClashX · $repository',
                    onTap: () =>
                        globalState.openUrl('https://github.com/$repository'),
                  ),
                  _TributeRepoChip(
                    label: 'FlClash',
                    onTap: () => globalState
                        .openUrl('https://github.com/chen08209/FlClash'),
                  ),
                  _TributeRepoChip(
                    label: 'Mihomo',
                    onTap: () => globalState
                        .openUrl('https://github.com/MetaCubeX/mihomo'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 2. Special Engineering & Design Credit to Gemini 4
        Container(
          key: geminiCardKey,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colors.surfaceContainer,
            border: Border.all(color: hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1)
                          .withValues(alpha: isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 13,
                          color: isDark
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF4F46E5),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            appLocalizations.tributeGeminiBadge,
                            style: textTheme.labelSmall?.copyWith(
                              color: isDark
                                  ? const Color(0xFFA5B4FC)
                                  : const Color(0xFF4F46E5),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                appLocalizations.tributeGeminiTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appLocalizations.tributeGeminiBody,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TributeRepoChip extends StatelessWidget {
  const _TributeRepoChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_in_new_rounded,
                size: 13,
                color: colors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Commercial brand showcase content displayed inside the one-tap brand dialog
/// opened from the top-left emblem.
class FreedomNetBrandShowcase extends StatelessWidget {
  const FreedomNetBrandShowcase({super.key});

  String _safeClientVersion() {
    try {
      return globalState.packageInfo.version.trim();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = colors.brightness == Brightness.dark;
    final hairline = freedomNetHairlineColor(colors);
    final badgeFg = isDark ? kPortalBrandMarkBg : kPortalBrandMarkFg;
    final serviceAccent =
        isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5);
    final version = _safeClientVersion();

    return Column(
      key: const ValueKey('freedomnet-brand-showcase'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('freedomnet-brand-hero-card'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kPortalBrandMarkBg.withValues(alpha: isDark ? 0.14 : 0.12),
                colors.primary.withValues(alpha: isDark ? 0.08 : 0.05),
                colors.surfaceContainer,
              ],
            ),
            border: Border.all(
              color: kPortalBrandMarkBg.withValues(alpha: isDark ? 0.34 : 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kPortalBrandMarkBg.withValues(
                        alpha: isDark ? 0.18 : 0.22,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: badgeFg,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            appLocalizations.brandShowcaseBadge,
                            style: textTheme.labelSmall?.copyWith(
                              color: badgeFg,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (version.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: hairline),
                      ),
                      child: Text(
                        'v$version',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                appLocalizations.brandShowcaseHeroTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                appLocalizations.brandShowcaseHeroBody,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _BrandShowcasePillarTile(
          tileKey: const ValueKey('freedomnet-brand-pillar-smart'),
          icon: Icons.bolt_rounded,
          accentColor: kLatencyFastColor,
          title: appLocalizations.brandPillarSmartTitle,
          body: appLocalizations.brandPillarSmartBody,
        ),
        const SizedBox(height: 10),
        _BrandShowcasePillarTile(
          tileKey: const ValueKey('freedomnet-brand-pillar-modes'),
          icon: Icons.tune_rounded,
          accentColor: colors.primary,
          title: appLocalizations.brandPillarModesTitle,
          body: appLocalizations.brandPillarModesBody,
        ),
        const SizedBox(height: 10),
        _BrandShowcasePillarTile(
          tileKey: const ValueKey('freedomnet-brand-pillar-service'),
          icon: Icons.verified_user_rounded,
          accentColor: serviceAccent,
          title: appLocalizations.brandPillarServiceTitle,
          body: appLocalizations.brandPillarServiceBody,
        ),
      ],
    );
  }
}

class _BrandShowcasePillarTile extends StatelessWidget {
  const _BrandShowcasePillarTile({
    required this.tileKey,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.body,
  });

  final Key tileKey;
  final IconData icon;
  final Color accentColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = colors.brightness == Brightness.dark;
    final hairline = freedomNetHairlineColor(colors);

    return Container(
      key: tileKey,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colors.surfaceContainer,
        border: Border.all(color: hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 18,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showFreedomNetTributeDialog(BuildContext context) {
  final isZh = Localizations.localeOf(context)
      .languageCode
      .toLowerCase()
      .startsWith('zh');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      final textTheme = Theme.of(dialogContext).textTheme;
      return AlertDialog(
        key: const ValueKey('freedomnet-tribute-dialog'),
        titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Row(
          children: [
            const FreedomNetBrandMark(size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        appLocalizations.appBrandName,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (isZh)
                        Text(
                          brandNameEn,
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    appLocalizations.brandDialogSubtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const SingleChildScrollView(
            child: FreedomNetBrandShowcase(),
          ),
        ),
        actions: [
          FilledButton.tonal(
            key: const ValueKey('freedomnet-tribute-dialog-close'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel),
          ),
        ],
      );
    },
  );
}
