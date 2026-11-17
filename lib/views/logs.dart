import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../widgets/widgets.dart';

class LogsView extends ConsumerStatefulWidget {
  const LogsView({super.key});

  @override
  ConsumerState<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends ConsumerState<LogsView> with PageMixin {
  final _logsStateNotifier = ValueNotifier<LogsState>(
    const LogsState(loading: false),
  );
  late ScrollController _scrollController;

  double _currentMaxWidth = 0;
  static const _tag = CacheTag.logs;
  bool _isCurrentPage = false;
  bool _dirtyWhileHidden = false;

  List<Log> _logs = [];

  @override
  void initState() {
    super.initState();
    globalState.cacheHeightMap[_tag] ??= FixedMap(maxLength);
    final position = globalState.cacheScrollPosition[_tag] ?? -1;
    _scrollController = ScrollController(
      initialScrollOffset: position > 0 ? position : double.maxFinite,
    );
    _logs = globalState.appState.logs.list;
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
      logs: _logs,
      loading: false,
    );
    ref.listenManual(
      isCurrentPageProvider(
        PageLabel.logs,
        handler: (pageLabel, viewMode) =>
            pageLabel == PageLabel.tools && viewMode == ViewMode.mobile,
      ),
      (prev, next) {
        _isCurrentPage = next;
        if (prev != next && next == true) {
          initPageState();
          if (_dirtyWhileHidden) {
            _dirtyWhileHidden = false;
            updateLogsThrottler();
          }
        }
      },
      fireImmediately: true,
    );
    ref.listenManual(
      logsProvider.select((state) => state.list),
      (prev, next) {
        if (identical(prev, next)) return;
        _logs = next;
        if (!_isCurrentPage) {
          _dirtyWhileHidden = true;
          return;
        }
        if (!logListEquality.equals(prev, next)) {
          updateLogsThrottler();
        }
      },
    );
  }

  @override
  List<Widget> get actions => [
        IconButton(
          onPressed: _handleExport,
          icon: const Icon(
            Icons.file_download_outlined,
          ),
        ),
      ];

  @override
  Null Function(String value) get onSearch => (value) {
        _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
          query: value,
        );
      };

  @override
  Null Function(List<String> keywords) get onKeywordsUpdate => (keywords) {
        _logsStateNotifier.value =
            _logsStateNotifier.value.copyWith(keywords: keywords);
      };

  @override
  void dispose() {
    _logsStateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    final commonScaffoldState = context.commonScaffoldState;
    final res = await commonScaffoldState?.loadingRun<bool>(
      () async => globalState.appController.exportLogs(),
      title: appLocalizations.exportLogs,
    );
    if (res != true) return;
    globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.exportSuccess),
    );
  }

  double _getItemHeight(Log log) {
    final measure = globalState.measure;
    final bodySmallHeight = measure.bodySmallHeight;
    final bodyMediumHeight = measure.bodyMediumHeight;
    final height = globalState.measure
        .computeTextSize(
          Text(
            log.payload,
            style: context.textTheme.bodyLarge,
          ),
          maxWidth: _currentMaxWidth,
        )
        .height;
    return height + bodySmallHeight + 8 + bodyMediumHeight + 40 + 8;
  }

  void updateLogsThrottler() {
    throttler.call(FunctionTag.logs, () {
      if (!mounted || !_isCurrentPage) return;
      final isEquality = logListEquality.equals(
        _logs,
        _logsStateNotifier.value.logs,
      );
      if (isEquality) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
            logs: _logs,
          );
        }
      });
    }, duration: commonDuration);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, constraints) {
          final nextWidth = constraints.maxWidth - 40;
          if (_currentMaxWidth != nextWidth) {
            _currentMaxWidth = nextWidth;
            globalState.cacheHeightMap[_tag]?.clear();
          }
          return ValueListenableBuilder<LogsState>(
            valueListenable: _logsStateNotifier,
            builder: (_, state, __) {
              final logs = state.list;
              final itemCount = logs.isEmpty ? 0 : logs.length * 2 - 1;
              final content = logs.isEmpty
                  ? NullStatus(
                      label: appLocalizations.nullTip(
                        appLocalizations.logs,
                      ),
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: CommonScrollBar(
                        controller: _scrollController,
                        child: ScrollToEndBox(
                          controller: _scrollController,
                          tag: _tag,
                          dataSource: logs,
                          child: CacheItemExtentListView(
                            tag: _tag,
                            reverse: true,
                            shrinkWrap: false,
                            physics: const NextClampingScrollPhysics(),
                            controller: _scrollController,
                            itemBuilder: (_, index) {
                              if (index.isOdd) {
                                return const Divider(height: 0);
                              }
                              final log = logs[index ~/ 2];
                              return LogItem(
                                key: ValueKey('${log.dateTime}#${index ~/ 2}'),
                                log: log,
                                onClick: (value) {
                                  context.commonScaffoldState?.addKeyword(value);
                                },
                              );
                            },
                            itemExtentBuilder: (index) {
                              if (index.isOdd) {
                                return 0;
                              }
                              return _getItemHeight(logs[index ~/ 2]);
                            },
                            itemCount: itemCount,
                            keyBuilder: (index) {
                              if (index.isOdd) {
                                return 'divider#${index ~/ 2}';
                              }
                              final log = logs[index ~/ 2];
                              return '${log.dateTime}#${index ~/ 2}#${log.payload.hashCode}';
                            },
                          ),
                        ),
                      ),
                    );
              return FadeBox(
                child: state.loading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : content,
              );
            },
          );
        },
      );
}

class LogItem extends StatelessWidget {
  const LogItem({
    super.key,
    required this.log,
    this.onClick,
  });
  final Log log;
  final Function(String)? onClick;

  @override
  Widget build(BuildContext context) => ListItem(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        title: SelectableText(
          log.payload,
          style: context.textTheme.bodyLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              log.dateTime,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.primary,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Container(
              alignment: Alignment.centerLeft,
              child: CommonChip(
                onPressed: () {
                  if (onClick == null) return;
                  onClick!(log.logLevel.name);
                },
                label: log.logLevel.name,
              ),
            ),
          ],
        ),
      );
}
