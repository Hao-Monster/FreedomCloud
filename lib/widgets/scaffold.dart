import 'package:cached_network_image/cached_network_image.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/day_night_sky_background.dart';
import 'package:flclashx/widgets/fade_box.dart';
import 'package:flclashx/widgets/pop_scope.dart';
import 'package:flclashx/widgets/search_order_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'chip.dart';

class CommonScaffold extends ConsumerStatefulWidget {

  const CommonScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.sideNavigationBar,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.leading,
    this.title,
    this.actions,
    this.persistentActions,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.appBarEditState,
    this.floatingActionButton,
    this.disableBackground = false,
  });

  CommonScaffold.open({
    Key? key,
    required Widget body,
    required String title,
    required Function onBack,
    required List<Widget> actions,
    bool disableBackground = false,
  }) : this(
          key: key,
          body: body,
          title: title,
          automaticallyImplyLeading: false,
          actions: actions,
          disableBackground: disableBackground,
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: () {
              onBack();
            },
          ),
        );
  final AppBar? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? sideNavigationBar;
  final Color? backgroundColor;
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final List<Widget>? persistentActions;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final AppBarEditState? appBarEditState;
  final FloatingActionButton? floatingActionButton;
  final bool disableBackground;

  @override
  ConsumerState<CommonScaffold> createState() => CommonScaffoldState();
}

class CommonScaffoldState extends ConsumerState<CommonScaffold> {
  static const double minInlineTitleAccessoryWidth = 1040.0;
  static const double maxInlineTitleAccessoryTextScale = 1.20;

  late final ValueNotifier<AppBarState> _appBarState;
  late final Listenable _headerSlotListenable;
  final ValueNotifier<Widget?> _floatingActionButton = ValueNotifier(null);
  final ValueNotifier<Widget?> _titleAccessory = ValueNotifier(null);
  final ValueNotifier<List<String>> _keywordsNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _loading = ValueNotifier(false);

  final _textController = TextEditingController();

  Function(List<String>)? _onKeywordsUpdate;
  Locale? _lastLocale;
  String? _lastIntlLocale;
  bool _hasRecordedLocale = false;
  bool _skyDaySurface = false;
  bool _hasSyncedSkySurface = false;

  void _handleSkyDaySurfaceChanged(bool isDaySurface) {
    if (!mounted) return;
    _hasSyncedSkySurface = true;
    if (_skyDaySurface != isDaySurface) {
      setState(() {
        _skyDaySurface = isDaySurface;
      });
    }
  }

  Widget? get _sideNavigationBar => widget.sideNavigationBar;

  bool get hasNavigationBar =>
      widget.sideNavigationBar != null || widget.bottomNavigationBar != null;

  set actions(List<Widget> actions) {
    _appBarState.value = _appBarState.value.copyWith(actions: actions);
  }

  bool get _isSearch => _appBarState.value.searchState?.isSearch == true;

  bool get _isEdit => _appBarState.value.editState?.isEdit == true;

  set onKeywordsUpdate(Function(List<String>)? onKeywordsUpdate) {
    _onKeywordsUpdate = onKeywordsUpdate;
  }

  @override
  void initState() {
    super.initState();
    _appBarState = ValueNotifier(
      AppBarState(
        editState: widget.appBarEditState,
      ),
    );
    _headerSlotListenable = Listenable.merge([_appBarState, _titleAccessory]);
  }

  void updateSearchState(
    AppBarSearchState? Function(AppBarSearchState? state) builder,
  ) {
    _appBarState.value = _appBarState.value.copyWith(
      searchState: builder(
        _appBarState.value.searchState,
      ),
    );
  }

  void updateEditState(
    AppBarEditState? Function(AppBarEditState? state) builder,
  ) {
    _appBarState.value = _appBarState.value.copyWith(
      editState: builder(
        _appBarState.value.editState,
      ),
    );
  }

  set floatingActionButton(Widget? floatingActionButton) {
    if (_floatingActionButton.value != floatingActionButton) {
      _floatingActionButton.value = floatingActionButton;
    }
  }

  Listenable get headerSlotListenable => _headerSlotListenable;

  Widget? get titleAccessory => _titleAccessory.value;

  set titleAccessory(Widget? widget) {
    if (_titleAccessory.value != widget) {
      _titleAccessory.value = widget;
    }
  }

  bool get isInlineTitleAccessoryActive =>
      isInlineTitleAccessoryActiveFor(context);

  /// Returns whether the inline AppBar title accessory is active for [callerContext].
  ///
  /// Registering [MediaQuery.maybeOf] on [callerContext] keeps AppBar and body
  /// listeners synchronized in the same frame across dynamic `textScale` and
  /// window width transitions.
  bool isInlineTitleAccessoryActiveFor(BuildContext callerContext) {
    if (!mounted ||
        !callerContext.mounted ||
        _isSearch ||
        _isEdit ||
        _titleAccessory.value == null) {
      return false;
    }
    final media = MediaQuery.maybeOf(callerContext);
    if (media == null) {
      return false;
    }
    return media.size.width >= minInlineTitleAccessoryWidth &&
        media.textScaler.scale(1.0) <= maxInlineTitleAccessoryTextScale;
  }

  Widget _buildSearchingAppBarTheme(
    BuildContext themeContext,
    Widget child,
  ) {
    final theme = Theme.of(themeContext);
    final colorScheme = theme.colorScheme;
    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: colorScheme.surfaceContainer,
          iconTheme: (theme.appBarTheme.iconTheme ?? theme.iconTheme).copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          titleTextStyle: theme.textTheme.titleLarge,
          toolbarTextStyle: theme.textTheme.bodyMedium,
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: theme.inputDecorationTheme.hintStyle,
          border: InputBorder.none,
        ),
      ),
      child: child,
    );
  }

  Future<T?> loadingRun<T>(
    Future<T> Function() futureFunction, {
    String? title,
  }) async {
    _loading.value = true;
    try {
      final res = await futureFunction();
      _loading.value = false;
      return res;
    } catch (e) {
      globalState.showMessage(
        title: title ?? appLocalizations.tip,
        message: TextSpan(
          text: e.toString(),
        ),
      );
      _loading.value = false;
      return null;
    }
  }

  void _handleClearInput() {
    _textController.text = "";

    if (_appBarState.value.searchState != null) {
      _appBarState.value.searchState!.onSearch("");
    }
  }

  void _handleClear() {
    if (_textController.text.isNotEmpty) {
      _handleClearInput();
      return;
    }
    updateSearchState(
      (state) => state?.copyWith(
        isSearch: false,
      ),
    );
  }

  void _handleExitSearching() {
    _handleClearInput();
    updateSearchState(
      (state) => state?.copyWith(
        isSearch: false,
      ),
    );
  }

  @override
  void dispose() {
    _appBarState.dispose();
    _textController.dispose();
    _floatingActionButton.dispose();
    _titleAccessory.dispose();
    _keywordsNotifier.dispose();
    _loading.dispose();
    super.dispose();
  }

  void _syncLocaleTracking() {
    _lastLocale = Localizations.maybeLocaleOf(context);
    _lastIntlLocale = Intl.getCurrentLocale();
    _hasRecordedLocale = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLocaleTracking();
  }

  @override
  void didUpdateWidget(CommonScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentLocale = Localizations.maybeLocaleOf(context);
    final currentIntlLocale = Intl.getCurrentLocale();
    final localeChanged = _hasRecordedLocale &&
        (currentLocale != _lastLocale ||
            currentIntlLocale != _lastIntlLocale);
    _lastLocale = currentLocale;
    _lastIntlLocale = currentIntlLocale;
    _hasRecordedLocale = true;

    if (oldWidget.title != widget.title && !localeChanged) {
      _appBarState.value = const AppBarState();
      _floatingActionButton.value = null;
      _titleAccessory.value = null;
      _textController.text = "";
      _keywordsNotifier.value = [];
      _onKeywordsUpdate = null;
    } else if (oldWidget.appBarEditState != widget.appBarEditState) {
      _appBarState.value = _appBarState.value.copyWith(
        editState: widget.appBarEditState,
      );
    }
  }

  void addKeyword(String keyword) {
    final isContains = _keywordsNotifier.value.contains(keyword);
    if (isContains) return;
    final keywords = List<String>.from(_keywordsNotifier.value)..add(keyword);
    _keywordsNotifier.value = keywords;
  }

  void _deleteKeyword(String keyword) {
    final isContains = _keywordsNotifier.value.contains(keyword);
    if (!isContains) return;
    final keywords = List<String>.from(_keywordsNotifier.value)
      ..remove(keyword);
    _keywordsNotifier.value = keywords;
  }

  Widget? _buildLeading() {
    if (_isEdit) {
      return IconButton(
        onPressed: _appBarState.value.editState?.onExit,
        icon: const Icon(Icons.close),
      );
    }
    return _isSearch
        ? IconButton(
            onPressed: _handleExitSearching,
            icon: const Icon(Icons.arrow_back),
          )
        : widget.leading;
  }

  Widget _buildTitle(
    AppBarSearchState? startState,
    BuildContext accessoryContext,
  ) {
    if (_isSearch) {
      return TextField(
        autofocus: true,
        controller: _textController,
        style: Theme.of(accessoryContext).textTheme.titleLarge,
        onChanged: (value) {
          if (startState != null) {
            startState.onSearch(value);
          }
        },
        decoration: InputDecoration(
          hintText: appLocalizations.search,
        ),
      );
    }
    if (_isEdit) {
      return Text(
        appLocalizations.selectedCountTitle(
          "${_appBarState.value.editState?.editCount ?? 0}",
        ),
      );
    }
    if (isInlineTitleAccessoryActiveFor(accessoryContext)) {
      return Row(
        children: [
          Flexible(
            flex: 0,
            child: Text(
              widget.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _titleAccessory.value!,
          ),
        ],
      );
    }
    return Text(widget.title!);
  }

  List<Widget> _buildActions(
    AppBarSearchState? searchState,
    List<Widget> actions,
  ) {
    if (_isSearch) {
      return genActions([
        IconButton(
          onPressed: _handleClear,
          icon: const Icon(Icons.close),
        ),
      ]);
    }

    final hasSearch = searchState != null;
    final searchButton = IconButton(
      onPressed: () {
        updateSearchState(
          (state) => state?.copyWith(
            isSearch: true,
          ),
        );
      },
      icon: const Icon(Icons.search),
    );

    final persistent = !_isEdit
        ? (widget.persistentActions ?? const <Widget>[])
        : const <Widget>[];

    if (!hasSearch) {
      return genActions([
        ...actions,
        ...persistent,
      ]);
    }

    // For Proxies page we want search at the end; for others keep default
    // Check for explicit marker widget in actions to control search placement
    final shouldPutSearchAtEnd = actions.any((w) => w is SearchOrderMarker);

    if (shouldPutSearchAtEnd) {
      return genActions([
        ...actions,
        searchButton,
        ...persistent,
      ]);
    }

    return genActions([
      searchButton,
      ...actions,
      ...persistent,
    ]);
  
  }

  Widget _buildAppBarWrap(BuildContext themeContext, Widget child) {
    final appBar =
        _isSearch ? _buildSearchingAppBarTheme(themeContext, child) : child;
    if (_isEdit || _isSearch) {
      return SystemBackBlock(
        child: CommonPopScope(
          onPop: () {
            if (_isEdit || _isSearch) {
              _handleExitSearching();
              _appBarState.value.editState?.onExit();
              return false;
            }
            return true;
          },
          child: appBar,
        ),
      );
    }
    return appBar;
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext themeContext, {
    required bool isTransparent,
  }) {
    final theme = Theme.of(themeContext);
    final colorScheme = theme.colorScheme;

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Theme(
        data: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  theme.brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
              systemNavigationBarIconBrightness:
                  theme.brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
              systemNavigationBarColor: widget.bottomNavigationBar != null
                  ? colorScheme.surfaceDim
                  : colorScheme.surface,
              systemNavigationBarDividerColor: Colors.transparent,
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            widget.appBar ??
                ListenableBuilder(
                  listenable: headerSlotListenable,
                  builder: (slotContext, _) {
                    final state = _appBarState.value;
                    final inlineActive =
                        isInlineTitleAccessoryActiveFor(slotContext);
                    final effectiveTransparent =
                        isTransparent && !_isSearch && !_isEdit;
                    return _buildAppBarWrap(
                      slotContext,
                      AppBar(
                        backgroundColor:
                            effectiveTransparent ? Colors.transparent : null,
                        elevation: effectiveTransparent ? 0 : null,
                        centerTitle:
                            inlineActive ? false : (widget.centerTitle ?? false),
                        automaticallyImplyLeading:
                            widget.automaticallyImplyLeading,
                        leading: _buildLeading(),
                        title: _buildTitle(state.searchState, slotContext),
                        actions: _buildActions(
                          state.searchState,
                          state.actions.isNotEmpty
                              ? state.actions
                              : widget.actions ?? [],
                        ),
                      ),
                    );
                  },
                ),
            ValueListenableBuilder(
              valueListenable: _loading,
              builder: (_, value, __) => value == true
                    ? const LinearProgressIndicator()
                    : Container(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(String? backgroundUrl) {
    if (backgroundUrl == null || backgroundUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: CachedNetworkImage(
        imageUrl: backgroundUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => const SizedBox.shrink(),
        errorWidget: (context, url, error) => const SizedBox.shrink(),
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, int? opacity) {
    // Dimming overlay over the background image. `opacity` (1-100, from the optional
    // `,<opacity>` suffix of flclashx-background) = how visible the image should be:
    // higher opacity → lower overlay alpha → more visible image. Unset → keep the
    // original hardcoded look (image ~10% visible).
    final double topAlpha;
    final double bottomAlpha;
    if (opacity == null) {
      topAlpha = 0.92;
      bottomAlpha = 0.88;
    } else {
      final base = (1 - opacity / 100).clamp(0.0, 1.0);
      topAlpha = base;
      bottomAlpha = (base - 0.04).clamp(0.0, 1.0);
    }
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              context.colorScheme.surface.withValues(alpha: topAlpha),
              context.colorScheme.surface.withValues(alpha: bottomAlpha),
            ],
          ),
        ),
      ),
    );
  }

  ThemeData _resolveSkyScaffoldTheme(
    BuildContext context, {
    required bool isDaySurface,
    required DayNightGlassPreset glassPreset,
  }) {
    final ambient = Theme.of(context);
    final targetBrightness = isDaySurface ? Brightness.light : Brightness.dark;
    final ThemeData baseTheme;
    if (ambient.brightness == targetBrightness) {
      baseTheme = ambient;
    } else {
      final colorScheme = ref.watch(genColorSchemeProvider(targetBrightness));
      final built = buildFreedomNetThemeData(
        colorScheme: colorScheme,
        pageTransitionsTheme: ambient.pageTransitionsTheme,
      );
      final ambientFont = ambient.textTheme.bodyMedium?.fontFamily;
      final builtFont = built.textTheme.bodyMedium?.fontFamily;
      if (ambientFont != null && ambientFont != builtFont) {
        baseTheme = built.copyWith(
          textTheme: built.textTheme.apply(fontFamily: ambientFont),
          appBarTheme: built.appBarTheme.copyWith(
            titleTextStyle: built.appBarTheme.titleTextStyle?.copyWith(
              fontFamily: ambientFont,
            ),
          ),
        );
      } else {
        baseTheme = built;
      }
    }

    final scheme = baseTheme.colorScheme;
    final hairline = freedomNetHairlineColor(scheme);
    final glass = resolveDayNightGlassAlphas(
      preset: glassPreset,
      isDaySurface: isDaySurface,
    );
    final translucentCard =
        scheme.surfaceContainer.withValues(alpha: glass.scaffoldCard);
    final translucentChip =
        scheme.surfaceContainerHigh.withValues(alpha: glass.scaffoldChip);

    return baseTheme.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      cardColor: translucentCard,
      cardTheme: baseTheme.cardTheme.copyWith(
        elevation: 0,
        color: translucentCard,
        surfaceTintColor: Colors.transparent,
        shape: baseTheme.cardTheme.shape ??
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: hairline),
            ),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: translucentChip,
      ),
    );
  }

  Widget _buildScaffoldShell(
    BuildContext themeContext, {
    required Widget body,
    required bool isTransparent,
  }) =>
      Scaffold(
        appBar: _buildAppBar(themeContext, isTransparent: isTransparent),
        body: body,
        resizeToAvoidBottomInset: true,
        backgroundColor: isTransparent
            ? (widget.backgroundColor ?? Colors.transparent)
            : widget.backgroundColor,
        floatingActionButton: widget.floatingActionButton ??
            ValueListenableBuilder<Widget?>(
              valueListenable: _floatingActionButton,
              builder: (_, value, __) => IntrinsicWidth(
                child: IntrinsicHeight(
                  child: FadeScaleBox(
                    child: value ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        bottomNavigationBar: widget.bottomNavigationBar,
      );

  @override
  Widget build(BuildContext context) {
    assert(
      widget.appBar != null || widget.title != null,
      'CommonScaffold requires either appBar or title',
    );
    final backgroundUrl =
        widget.disableBackground ? null : ref.watch(backgroundUrlProvider);
    final hasCustomBackground =
        backgroundUrl != null && backgroundUrl.isNotEmpty;
    final (skyMode, glassPreset, ignoreCustomBackground) =
        widget.disableBackground
            ? (
                DayNightSkyMode.followConnection,
                DayNightGlassPreset.balanced,
                false,
              )
            : ref.watch(
                themeSettingProvider.select(
                  (state) => (
                    state.skyMode,
                    state.glassPreset,
                    state.ignoreCustomBackground,
                  ),
                ),
              );
    final useCustomBackground = hasCustomBackground && !ignoreCustomBackground;
    final useSkyBackground = !widget.disableBackground && !useCustomBackground;
    final isRunning = useSkyBackground
        ? ref.watch(runTimeProvider.select((state) => state != null))
        : false;
    final pendingTarget =
        useSkyBackground ? ref.watch(statusSwitchPendingProvider) : null;
    final targetPhase = resolveDayNightSkyPhase(
      isRunning: isRunning,
      pendingTarget: pendingTarget,
      mode: skyMode,
    );
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!useSkyBackground) {
      _hasSyncedSkySurface = false;
    } else if (!_hasSyncedSkySurface || reduceMotion) {
      _skyDaySurface = targetPhase == DayNightSkyPhase.day;
      _hasSyncedSkySurface = true;
    }

    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder(
            valueListenable: _keywordsNotifier,
            builder: (_, keywords, __) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_onKeywordsUpdate != null) {
                  _onKeywordsUpdate!(keywords);
                }
              });
              if (keywords.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    for (final keyword in keywords)
                      CommonChip(
                        label: keyword,
                        type: ChipType.delete,
                        onPressed: () {
                          _deleteKeyword(keyword);
                        },
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: widget.body,
          ),
        ],
      ),
    );

    ThemeData? skyTheme;
    final Widget scaffoldWithBackground;
    if (useCustomBackground) {
      scaffoldWithBackground = Stack(
        children: [
          _buildBackground(backgroundUrl),
          _buildOverlay(
            context,
            widget.disableBackground
                ? null
                : ref.watch(backgroundOpacityProvider),
          ),
          _buildScaffoldShell(context, body: body, isTransparent: true),
        ],
      );
    } else if (useSkyBackground) {
      skyTheme = _resolveSkyScaffoldTheme(
        context,
        isDaySurface: _skyDaySurface,
        glassPreset: glassPreset,
      );
      scaffoldWithBackground = Builder(
        builder: (skyContext) => Stack(
          children: [
            Positioned.fill(
              child: DayNightSkyBackground(
                onDaySurfaceChanged: _handleSkyDaySurfaceChanged,
              ),
            ),
            _buildScaffoldShell(
              skyContext,
              body: body,
              isTransparent: true,
            ),
          ],
        ),
      );
    } else {
      scaffoldWithBackground = _buildScaffoldShell(
        context,
        body: body,
        isTransparent: false,
      );
    }

    final layout = _sideNavigationBar != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sideNavigationBar!,
              Expanded(
                flex: 1,
                child: scaffoldWithBackground,
              ),
            ],
          )
        : scaffoldWithBackground;

    if (skyTheme != null) {
      return Theme(
        data: skyTheme,
        child: DayNightSkyScope(
          isActive: true,
          isDaySurface: _skyDaySurface,
          glassPreset: glassPreset,
          child: layout,
        ),
      );
    }
    return layout;
  }
}

List<Widget> genActions(List<Widget> actions, {double? space}) => <Widget>[
    ...actions.separated(
      SizedBox(
        width: space ?? 4,
      ),
    ),
    const SizedBox(
      width: 8,
    )
  ];
