import 'dart:math';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkSpeed extends StatefulWidget {
  const NetworkSpeed({super.key});

  @override
  State<NetworkSpeed> createState() => _NetworkSpeedState();
}

class _NetworkSpeedState extends State<NetworkSpeed> {
  static const List<Point> _initPoints = [Point(0, 0), Point(1, 0)];

  List<Point> _getPoints(List<Traffic> traffics) {
    final trafficPoints = traffics
        .asMap()
        .entries
        .map(
          (entry) => Point(
            (entry.key + _initPoints.length).toDouble(),
            entry.value.speed.toDouble(),
          ),
        )
        .toList();

    return [..._initPoints, ...trafficPoints];
  }

  Traffic _getLastTraffic(List<Traffic> traffics) {
    if (traffics.isEmpty) return Traffic();
    return traffics.last;
  }

  Widget _buildLegendItem(
    BuildContext context, {
    required Color color,
    required String label,
  }) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 7,
            decoration: ShapeDecoration(
              color: color,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,
            ),
          ),
        ],
      );

  Widget _buildTrafficDataItem(
    BuildContext context, {
    required IconData iconData,
    required Color iconColor,
    required TrafficValue trafficValue,
  }) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  iconData,
                  color: iconColor,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    trafficValue.showValue,
                    style: context.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 0,
            child: Text(
              trafficValue.showUnit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.toLighter,
            ),
          ),
        ],
      );

  Widget _buildSpeedPanel(
    BuildContext context, {
    required bool isStacked,
  }) {
    final headerColor = context.colorScheme.onSurfaceVariant;
    final speedTextColor = headerColor.opacity80;

    final titleGroup = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.speed_sharp,
          size: 20,
          color: headerColor,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: TooltipText(
            text: Text(
              appLocalizations.networkSpeed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleSmall?.copyWith(
                color: headerColor,
              ),
            ),
          ),
        ),
      ],
    );

    final speedReadout = RepaintBoundary(
      child: ExcludeSemantics(
        child: Consumer(
          builder: (context, ref, _) {
            final traffics = ref.watch(trafficsProvider).list;
            final lastTraffic = _getLastTraffic(traffics);
            final liveSpeedLabel = '${lastTraffic.up}↑   ${lastTraffic.down}↓';
            final speedText = Text(
              liveSpeedLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: speedTextColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
            if (isStacked) {
              return speedText;
            }
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: speedText,
            );
          },
        ),
      ),
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 0),
      child: isStacked
          ? Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                titleGroup,
                speedReadout,
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: titleGroup),
                const SizedBox(width: 8),
                Flexible(child: speedReadout),
              ],
            ),
    );

    final chart = RepaintBoundary(
      child: ExcludeSemantics(
        child: Consumer(
          builder: (context, ref, _) {
            final traffics = ref.watch(trafficsProvider).list;
            return ClipRect(
              child: Padding(
                padding: EdgeInsets.only(top: isStacked ? 10 : 14),
                child: LineChart(
                  gradient: true,
                  color: context.colorScheme.primary,
                  points: _getPoints(traffics),
                ),
              ),
            );
          },
        ),
      ),
    );

    return Column(
      mainAxisSize: isStacked ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (isStacked)
          SizedBox(
            height: 92,
            child: chart,
          )
        else
          Expanded(child: chart),
      ],
    );
  }

  Widget _buildTrafficPanel(
    BuildContext context, {
    required Color primaryColor,
    required Color secondaryColor,
    required bool isStacked,
    required double textScale,
  }) {
    final headerColor = context.colorScheme.onSurfaceVariant;

    return Consumer(
      builder: (context, ref, _) {
        final totalTraffic = ref.watch(totalTrafficProvider);
        final upTotalTrafficValue = totalTraffic.up;
        final downTotalTrafficValue = totalTraffic.down;

        final header = Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Row(
            children: [
              Icon(
                Icons.data_saver_off,
                size: 20,
                color: headerColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TooltipText(
                  text: Text(
                    appLocalizations.trafficUsage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: headerColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        final donutAndLegend = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: isStacked ? 10 : 8,
          ),
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: DonutChart(
                  data: [
                    DonutChartData(
                      value: upTotalTrafficValue.value.toDouble(),
                      color: primaryColor,
                    ),
                    DonutChartData(
                      value: downTotalTrafficValue.value.toDouble(),
                      color: secondaryColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, legendConstraints) {
                    if (legendConstraints.maxWidth < 36) {
                      return const SizedBox.shrink();
                    }
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: legendConstraints.maxWidth,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLegendItem(
                                context,
                                color: primaryColor,
                                label: appLocalizations.upload,
                              ),
                              const SizedBox(height: 5),
                              _buildLegendItem(
                                context,
                                color: secondaryColor,
                                label: appLocalizations.download,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );

        final totalsFooter = Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTrafficDataItem(
                context,
                iconData: Icons.arrow_upward,
                iconColor: primaryColor,
                trafficValue: upTotalTrafficValue,
              ),
              const SizedBox(height: 6),
              _buildTrafficDataItem(
                context,
                iconData: Icons.arrow_downward,
                iconColor: secondaryColor,
                trafficValue: downTotalTrafficValue,
              ),
            ],
          ),
        );

        return Column(
          mainAxisSize: isStacked ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (isStacked)
              SizedBox(
                height: max(76.0, 44.0 * textScale),
                child: donutAndLegend,
              )
            else
              Expanded(child: donutAndLegend),
            totalsFooter,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = context.colorScheme.primary;
    final secondaryColor = Color.lerp(
      context.colorScheme.primary,
      context.colorScheme.onSurfaceVariant,
      0.62,
    )!;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return CommonCard(
      key: const ValueKey('dashboard-network-traffic-card'),
      onPressed: () {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSideBySide =
              constraints.maxWidth >= 340 && textScale <= 1.45;
          final dividerColor =
              context.colorScheme.outlineVariant.withValues(alpha: 0.38);

          if (isSideBySide) {
            return SizedBox(
              height: max(getWidgetHeight(2), 188.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 58,
                    child: _buildSpeedPanel(
                      context,
                      isStacked: false,
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.only(top: 12),
                    color: dividerColor,
                  ),
                  Expanded(
                    flex: 42,
                    child: _buildTrafficPanel(
                      context,
                      primaryColor: primaryColor,
                      secondaryColor: secondaryColor,
                      isStacked: false,
                      textScale: textScale,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSpeedPanel(
                context,
                isStacked: true,
              ),
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: dividerColor,
              ),
              _buildTrafficPanel(
                context,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                isStacked: true,
                textScale: textScale,
              ),
            ],
          );
        },
      ),
    );
  }
}
