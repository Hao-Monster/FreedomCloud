import 'dart:async';

import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/signed_update_dialog.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';

@immutable
class Contributor {
  const Contributor({
    this.avatar,
    required this.name,
    required this.link,
    this.clickable = true,
  });
  final String? avatar;
  final String name;
  final String link;
  final bool clickable;
}

@immutable
class ThanksPerson {
  const ThanksPerson({
    this.avatar,
    required this.name,
  });
  final String? avatar;
  final String name;
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  Future<void> _checkUpdate(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SignedUpdateDialog(),
    );
  }

  Widget _buildBrandMonument(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = colors.brightness == Brightness.dark;
    final isZh = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');

    return Container(
      key: const ValueKey('about-brand-monument'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: isDark ? 0.14 : 0.08),
            colors.surfaceContainer,
          ],
        ),
        border: Border.all(
          color: freedomNetHairlineColor(colors),
        ),
      ),
      child: _EasterEggDetector(
        onEasterEgg: () {
          unawaited(
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => AlertDialog(
                title: const Text(
                  'REMNAFAMILY ONE LOVE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '❤️',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 48),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () {
                        unawaited(globalState.openUrl('https://docs.rw'));
                      },
                      child: const Text(
                        'TRY REMNAWAVE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.blue,
                          fontFamily: 'Unbounded',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const FreedomNetBrandMark(size: 58),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          appLocalizations.appBrandName,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (isZh)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary
                                  .withValues(alpha: isDark ? 0.16 : 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              brandNameEn,
                              style: textTheme.labelMedium?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appLocalizations.appBrandTagline,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'v${globalState.packageInfo.version}',
                            style: textTheme.labelMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const _CoreVersionWidget(),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildThanksForContributionSection(BuildContext context) {
    const contributors = [
      Contributor(
        avatar: "assets/images/avatars/x_kit_.jpg",
        name: "x_kit_",
        link: "https://github.com/this-xkit",
      ),
      Contributor(
        avatar: "assets/images/avatars/katsukibtw.jpg",
        name: "katsukibtw",
        link: "https://github.com/katsukibtw",
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.thanks,
      items: [
        ListItem(
          title: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final contributor in contributors)
                Avatar(
                  contributor: contributor,
                  size: 48.0,
                ),
            ],
          ),
        )
      ],
    );
  }

  List<Widget> _buildGratitudeSection(BuildContext context) {
    const gratitude = [
      ThanksPerson(
        name: "cool_coala",
        avatar: "assets/images/avatars/cool_coala.jpg",
      ),
      ThanksPerson(
        name: "arpic",
        avatar: "assets/images/avatars/arpic.jpg",
      ),
      ThanksPerson(
        name: "legiz",
        avatar: "assets/images/avatars/legiz.jpg",
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.gratitude,
      items: [
        ListItem(
          title: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final person in gratitude)
                SizedBox(
                  width: 76,
                  child: ThanksAvatar(
                    person: person,
                  ),
                ),
            ],
          ),
        )
      ],
    );
  }

  List<Widget> _buildMoreSection(BuildContext context) => generateSection(
        separated: false,
        title: appLocalizations.more,
        items: [
          ListItem(
            title: Text(appLocalizations.checkUpdate),
            onTap: () {
              unawaited(_checkUpdate(context));
            },
            trailing: const Icon(Icons.update),
          ),
          // Standalone core updates stay hidden until R-206 provides signature
          // verification and rollback for privileged desktop cores.
          ListItem(
            title: Text('${appLocalizations.project} (FlClashX)'),
            onTap: () {
              unawaited(
                globalState.openUrl(
                  "https://github.com/$repository",
                ),
              );
            },
            trailing: const Icon(Icons.insert_link),
          ),
          ListItem(
            title: Text(appLocalizations.originalRepository),
            onTap: () {
              unawaited(
                globalState.openUrl(
                  "https://github.com/chen08209/FlClash",
                ),
              );
            },
            trailing: const Icon(Icons.insert_link),
          ),
          ListItem(
            title: Text(appLocalizations.core),
            onTap: () {
              unawaited(
                globalState.openUrl(
                  "https://github.com/MetaCubeX/mihomo",
                ),
              );
            },
            trailing: const Icon(Icons.insert_link),
          ),
        ],
      );

  List<Widget> _buildContributorsSection() {
    const contributors = [
      Contributor(
        avatar: "assets/images/avatars/pluralplay.jpg",
        name: "pluralplay",
        link: "https://github.com/pluralplay",
      ),
      Contributor(
        avatar: "assets/images/avatars/kastov.jpg",
        name: "kastov",
        link: "https://github.com/kastov",
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.otherContributors,
      items: [
        ListItem(
          title: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final contributor in contributors)
                Avatar(
                  contributor: contributor,
                ),
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _buildBrandMonument(context),
      const SizedBox(height: 14),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: FreedomNetTributeCards(
          flclashxCardKey: ValueKey('about-tribute-flclashx'),
          geminiCardKey: ValueKey('about-tribute-gemini4'),
        ),
      ),
      const SizedBox(height: 16),
      ..._buildContributorsSection(),
      ..._buildThanksForContributionSection(context),
      ..._buildGratitudeSection(context),
      ..._buildMoreSection(context),
    ];
    return Padding(
      padding: kMaterialListPadding.copyWith(
        top: 16,
        bottom: 16,
      ),
      child: generateListView(items),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.contributor,
    this.size = 56.0,
  });
  final Contributor contributor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarSize = size;
    final fontSize = size * 0.25; // 14.0 for 56px
    final avatarFontSize = size * 0.46; // 26.0 for 56px

    final avatarWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: CircleAvatar(
            foregroundImage: contributor.avatar != null
                ? AssetImage(contributor.avatar!) as ImageProvider
                : null,
            backgroundColor: contributor.avatar == null
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: contributor.avatar == null
                ? Text(
                    contributor.name[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontFamily: 'Unbounded',
                      fontSize: avatarFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          contributor.name,
          style: TextStyle(
            fontFamily: 'Unbounded',
            fontSize: fontSize,
          ),
        )
      ],
    );

    if (contributor.clickable) {
      return Semantics(
        container: true,
        button: true,
        link: true,
        label: contributor.name,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              unawaited(globalState.openUrl(contributor.link));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: ExcludeSemantics(
                child: avatarWidget,
              ),
            ),
          ),
        ),
      );
    }

    return avatarWidget;
  }
}

class ThanksAvatar extends StatelessWidget {
  const ThanksAvatar({
    super.key,
    required this.person,
  });
  final ThanksPerson person;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 36.0;
    const fontSize = 9.0;
    const avatarFontSize = 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: CircleAvatar(
            foregroundImage: person.avatar != null
                ? AssetImage(person.avatar!) as ImageProvider
                : null,
            backgroundColor: person.avatar == null
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: person.avatar == null
                ? Text(
                    person.name[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontFamily: 'Unbounded',
                      fontSize: avatarFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        Text(
          person.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Unbounded',
            fontSize: fontSize,
          ),
        )
      ],
    );
  }
}

class _CoreVersionWidget extends StatelessWidget {
  const _CoreVersionWidget();

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        // Passive read: only query an already-instantiated core so opening
        // AboutView while stopped never constructs clashService as a side effect.
        future: ClashCore.existingCore != null
            ? clashCore.getCoreVersion()
            : Future<String>.value(''),
        builder: (context, snapshot) {
          final live = snapshot.data;
          final coreVersion =
              live != null && live.isNotEmpty ? live : globalState.coreVersion;
          if (coreVersion == null || coreVersion.isEmpty) {
            return const SizedBox.shrink();
          }
          final colors = Theme.of(context).colorScheme;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Core: $coreVersion',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          );
        },
      );
}

class _EasterEggDetector extends StatefulWidget {
  const _EasterEggDetector({
    required this.child,
    required this.onEasterEgg,
  });
  final Widget child;
  final VoidCallback onEasterEgg;

  @override
  State<_EasterEggDetector> createState() => _EasterEggDetectorState();
}

class _EasterEggDetectorState extends State<_EasterEggDetector> {
  int _counter = 0;
  Timer? _timer;

  void _handleTap() {
    _counter++;
    if (_counter >= 10) {
      widget.onEasterEgg();
      _resetCounter();
    } else {
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 1), _resetCounter);
    }
  }

  void _resetCounter() {
    _counter = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _handleTap,
        child: widget.child,
      );
}
