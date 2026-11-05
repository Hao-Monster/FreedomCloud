import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StartButton extends ConsumerStatefulWidget {
  const StartButton({super.key});

  @override
  ConsumerState<StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends ConsumerState<StartButton>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _pressController;
  late Animation<double> _animation;
  late Animation<double> _scaleAnimation;
  bool isStart = false;
  bool _localPending = false;
  bool? _localTargetStart;

  @override
  void initState() {
    super.initState();
    isStart = globalState.appState.runTime != null;
    _controller = AnimationController(
      vsync: this,
      value: isStart ? 1 : 0,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: Curves.easeOut,
      ),
    );

    ref.listenManual(
      runTimeProvider.select((state) => state != null),
      (prev, next) {
        if (next != isStart) {
          isStart = next;
          updateController();
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pressController.dispose();
    super.dispose();
  }

  Future<void> handleSwitchStart() async {
    _pressController.reverse();
    final providerPending = ref.read(statusSwitchPendingProvider);
    final startCancelable = ref.read(statusStartCancelableProvider);
    if (providerPending != null) {
      if (providerPending && startCancelable) {
        if (Platform.isAndroid) {
          unawaited(HapticFeedback.mediumImpact());
        }
        await globalState.appController.updateStatus(false);
      }
      return;
    }
    if (_localPending) {
      return;
    }
    if (Platform.isAndroid) {
      unawaited(HapticFeedback.mediumImpact());
    }
    final targetStart = !isStart;
    setState(() {
      _localPending = true;
      _localTargetStart = targetStart;
    });
    try {
      await globalState.appController.updateStatus(targetStart);
    } finally {
      if (mounted) {
        final actualStart = ref.read(runTimeProvider) != null;
        setState(() {
          _localPending = false;
          _localTargetStart = null;
          isStart = actualStart;
        });
        updateController();
      }
    }
  }

  void updateController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isStart) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _onTapDown(TapDownDetails details) {
    _pressController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _pressController.reverse();
  }

  void _onTapCancel() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(startButtonSelectorStateProvider);
    if (!state.isInit || !state.hasProfile) {
      return Container();
    }
    final providerPending = ref.watch(statusSwitchPendingProvider);
    final startCancelable = ref.watch(statusStartCancelableProvider);
    final runTime = ref.watch(runTimeProvider);
    final effectiveStart = runTime != null;
    final pendingTarget = providerPending ?? (_localPending ? _localTargetStart : null);
    final isBusy = pendingTarget != null;
    final canTapPress = !isBusy || (pendingTarget && startCancelable);

    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = Colors.green.shade600.withValues(alpha: 0.9);
    final inactiveColor = colorScheme.secondaryContainer.withValues(alpha: 0.85);
    final showActivePalette = isBusy ? !pendingTarget : effectiveStart;
    final foregroundColor = showActivePalette
        ? Colors.white
        : colorScheme.onSecondaryContainer;

    final Widget? statusLabelWidget;
    if (isBusy) {
      final pendingText = pendingTarget
          ? appLocalizations.tunStatusStarting
          : appLocalizations.tunStatusStopping;
      statusLabelWidget = Text(
        pendingText,
        key: ValueKey('pending_$pendingTarget'),
        style: context.textTheme.titleMedium?.toSoftBold.copyWith(
          color: foregroundColor,
        ),
      );
    } else if (runTime != null) {
      final text = utils.getTimeText(runTime);
      statusLabelWidget = Text(
        text,
        key: ValueKey('time_$text'),
        style: context.textTheme.titleMedium?.toSoftBold.copyWith(
          color: Colors.white,
        ),
      );
    } else {
      statusLabelWidget = null;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _pressController]),
        builder: (_, __) => Transform.scale(
          scale: _scaleAnimation.value,
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: GestureDetector(
              onTapDown: canTapPress ? _onTapDown : null,
              onTapUp: canTapPress ? _onTapUp : null,
              onTapCancel: _onTapCancel,
              child: FilledButton(
                onPressed: handleSwitchStart,
                style: FilledButton.styleFrom(
                  backgroundColor: showActivePalette ? activeColor : inactiveColor,
                  foregroundColor: foregroundColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: showActivePalette ? 4 : 0,
                ),
                child: Center(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isBusy)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: foregroundColor,
                            ),
                          )
                        else
                          AnimatedIcon(
                            icon: AnimatedIcons.play_pause,
                            progress: _animation,
                            size: 36,
                            color: foregroundColor,
                          ),
                        if (statusLabelWidget != null) ...[
                          const SizedBox(width: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (childWidget, animation) {
                              final offsetAnimation = Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ));

                              return SlideTransition(
                                position: offsetAnimation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: childWidget,
                                ),
                              );
                            },
                            layoutBuilder: (currentChild, previousChildren) =>
                                Stack(
                              alignment: Alignment.center,
                              children: [
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            ),
                            child: statusLabelWidget,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
