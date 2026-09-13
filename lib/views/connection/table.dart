import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/material.dart';

import 'item.dart';
import 'settings.dart';

class ConnectionTable extends StatefulWidget {
  const ConnectionTable({
    super.key,
    required this.items,
    required this.columns,
    required this.columnWidths,
    required this.onColumnWidthsChanged,
    required this.onTap,
    required this.onClose,
  });

  final List<TrackedConnection> items;
  final List<String> columns;
  final Map<String, double> columnWidths;
  final ValueChanged<Map<String, double>> onColumnWidthsChanged;
  final ValueChanged<TrackedConnection> onTap;
  final ValueChanged<TrackedConnection> onClose;

  @override
  State<ConnectionTable> createState() => _ConnectionTableState();
}

class _ConnectionTableState extends State<ConnectionTable> {
  final _horizontalController = ScrollController();
  final _verticalController = ScrollController();
  late Map<String, double> _widths;
  String _sortColumn = 'time';
  ConnectionSortDirection _direction = ConnectionSortDirection.descending;

  @override
  void initState() {
    super.initState();
    _widths = Map.of(widget.columnWidths);
  }

  @override
  void didUpdateWidget(ConnectionTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columnWidths != widget.columnWidths) {
      _widths = Map.of(widget.columnWidths);
    }
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  double _width(String column) =>
      _widths[column] ?? _defaultColumnWidth(column);

  @override
  Widget build(BuildContext context) {
    final sorted = _sortItems(widget.items, _sortColumn, _direction);
    final width = widget.columns.fold<double>(
          0,
          (total, column) => total + _width(column),
        ) +
        52;
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        notificationPredicate: (notification) => notification.depth == 1,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Material(
                  color: context.colorScheme.surfaceContainerHighest,
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        for (final column in widget.columns)
                          _headerCell(context, column),
                        const SizedBox(width: 52),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _verticalController,
                    child: ListView.builder(
                      controller: _verticalController,
                      itemExtent: 52,
                      itemCount: sorted.length,
                      itemBuilder: (_, index) {
                        final item = sorted[index];
                        return InkWell(
                          onTap: () => widget.onTap(item),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: context.colorScheme.outlineVariant,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                for (final column in widget.columns)
                                  _dataCell(context, item, column),
                                SizedBox(
                                  width: 52,
                                  child: IconButton(
                                    onPressed: () => widget.onClose(item),
                                    icon: Icon(
                                      item.isActive
                                          ? Icons.link_off_rounded
                                          : Icons.delete_outline,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(BuildContext context, String column) {
    final selected = column == _sortColumn;
    return SizedBox(
      width: _width(column),
      child: Stack(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (selected) {
                  _direction = _direction == ConnectionSortDirection.ascending
                      ? ConnectionSortDirection.descending
                      : ConnectionSortDirection.ascending;
                } else {
                  _sortColumn = column;
                  _direction = ConnectionSortDirection.ascending;
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      connectionColumnLabel(column),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelLarge,
                    ),
                  ),
                  if (selected)
                    Icon(
                      _direction == ConnectionSortDirection.ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 15,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _widths[column] =
                        (_width(column) + details.delta.dx).clamp(72, 420);
                  });
                },
                onHorizontalDragEnd: (_) =>
                    widget.onColumnWidthsChanged(Map.unmodifiable(_widths)),
                child: const SizedBox(width: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataCell(
    BuildContext context,
    TrackedConnection item,
    String column,
  ) {
    if (column == 'status') {
      return SizedBox(
        width: _width(column),
        child: Icon(
          item.isActive ? Icons.circle : Icons.circle_outlined,
          size: 13,
          color: item.isActive
              ? Colors.green
              : context.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return SizedBox(
      width: _width(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          _columnValue(item, column),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodySmall,
        ),
      ),
    );
  }
}

double _defaultColumnWidth(String column) => switch (column) {
      'status' => 76,
      'time' => 150,
      'type' || 'network' || 'uid' => 90,
      'upload' || 'download' || 'uploadSpeed' || 'downloadSpeed' => 120,
      'processPath' || 'id' => 240,
      'source' || 'destination' || 'remoteDestination' => 180,
      'host' || 'sniffHost' || 'process' || 'rulePayload' || 'chains' => 170,
      _ => 140,
    };

String _columnValue(TrackedConnection item, String column) {
  final connection = item.connection;
  final metadata = connection.metadata;
  return switch (column) {
    'status' => item.isActive
        ? appLocalizations.connectionsActive
        : appLocalizations.connectionsClosed,
    'time' => connection.start.toLocal().toString(),
    'type' => metadata.type,
    'network' => metadata.network.toUpperCase(),
    'host' => metadata.host,
    'sniffHost' => metadata.sniffHost,
    'source' => _address(metadata.sourceIP, metadata.sourcePort),
    'destination' => _address(metadata.destinationIP, metadata.destinationPort),
    'remoteDestination' => metadata.remoteDestination,
    'process' => metadata.process,
    'processPath' => metadata.processPath,
    'rule' => connection.rule,
    'rulePayload' => connection.rulePayload,
    'chains' => connection.chains.join(' → '),
    'uploadSpeed' => connectionRate(item.uploadSpeed),
    'downloadSpeed' => connectionRate(item.downloadSpeed),
    'upload' => TrafficValue(value: connection.upload?.toInt()).show,
    'download' => TrafficValue(value: connection.download?.toInt()).show,
    'inbound' => metadata.inboundName,
    'uid' => '${metadata.uid}',
    'id' => connection.id,
    _ => '',
  };
}

String _address(String ip, String port) => formatConnectionAddress(ip, port);

List<TrackedConnection> _sortItems(
  List<TrackedConnection> source,
  String column,
  ConnectionSortDirection direction,
) {
  final result = List<TrackedConnection>.of(source)
    ..sort((left, right) {
      final leftValue = _sortableValue(left, column);
      final rightValue = _sortableValue(right, column);
      final comparison = leftValue is num && rightValue is num
          ? leftValue.compareTo(rightValue)
          : leftValue.toString().toLowerCase().compareTo(
                rightValue.toString().toLowerCase(),
              );
      return direction == ConnectionSortDirection.ascending
          ? comparison
          : -comparison;
    });
  return result;
}

Object _sortableValue(TrackedConnection item, String column) =>
    switch (column) {
      'time' => item.connection.start.microsecondsSinceEpoch,
      'upload' => item.connection.upload ?? 0,
      'download' => item.connection.download ?? 0,
      'uploadSpeed' => item.uploadSpeed,
      'downloadSpeed' => item.downloadSpeed,
      'uid' => item.connection.metadata.uid,
      'status' => item.isActive ? 1 : 0,
      _ => _columnValue(item, column),
    };
