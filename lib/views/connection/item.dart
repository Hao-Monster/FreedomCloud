import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/process_icon.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/plugins/app.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

const double kConnRowExtent = 88;

final _androidProcessIconCache =
    BoundedCache<String, Future<ImageProvider?>?>(maxEntries: 64);

String connectionProcessName(Metadata metadata, {bool applicationName = true}) {
  if (metadata.type.toLowerCase() == 'inner') return 'mihomo';
  if (metadata.process.isNotEmpty) {
    return applicationName
        ? path.basenameWithoutExtension(metadata.process)
        : metadata.process;
  }
  if (metadata.processPath.isNotEmpty) {
    final executable = path.basename(metadata.processPath);
    return applicationName
        ? path.basenameWithoutExtension(executable)
        : executable;
  }
  return metadata.sourceIP.isNotEmpty
      ? metadata.sourceIP
      : appLocalizations.unknown;
}

String connectionDestination(Connection connection) {
  final metadata = connection.metadata;
  final host = metadata.host.isNotEmpty
      ? metadata.host
      : metadata.sniffHost.isNotEmpty
          ? metadata.sniffHost
          : metadata.destinationIP;
  return metadata.destinationPort.isEmpty
      ? host
      : '$host:${metadata.destinationPort}';
}

String connectionRate(double value) =>
    '${TrafficValue(value: value.round()).show}/s';

class ProcessIcon extends StatelessWidget {
  const ProcessIcon({
    super.key,
    required this.process,
    required this.processPath,
    this.connectionType = '',
    this.size = 44,
    this.enabled = true,
  });

  final String process;
  final String processPath;
  final String connectionType;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return _fallback(context);
    final isInner =
        connectionType.toLowerCase() == 'inner' || process == 'mihomo';
    final resolvedPath = isInner ? Platform.resolvedExecutable : processPath;
    final future = switch (Platform.operatingSystem) {
      'android' when process.isNotEmpty => _androidProcessIconCache.putIfAbsent(
          process,
          () => app?.getPackageIcon(process),
        ),
      'windows' => windowsProcessIcon(resolvedPath),
      'linux' => linuxProcessIcon(resolvedPath, process),
      _ => null,
    };
    if (future == null) return _fallback(context);
    return FutureBuilder<ImageProvider?>(
      future: future,
      builder: (_, snapshot) {
        final image = snapshot.data;
        if (image == null) return _fallback(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.23),
          child: Image(
            image: image,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      },
    );
  }

  Widget _fallback(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(size * 0.23),
        ),
        child: Icon(
          Icons.apps_rounded,
          size: size * 0.55,
          color: context.colorScheme.onSurfaceVariant,
        ),
      );
}

class ProcessConnectionCard extends StatelessWidget {
  const ProcessConnectionCard({
    super.key,
    required this.group,
    required this.showIcon,
    required this.useApplicationName,
    required this.onTap,
  });

  final ProcessConnectionGroup group;
  final bool showIcon;
  final bool useApplicationName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final first = group.activeConnections.firstOrNull?.connection ??
        group.closedConnections.first.connection;
    final name = connectionProcessName(
      first.metadata,
      applicationName: useApplicationName,
    );
    final muted = context.colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ProcessIcon(
                process: group.name,
                processPath: group.processPath,
                connectionType: first.metadata.type,
                enabled: showIcon,
                size: 50,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (group.activeCount > 0) ...[
                          const SizedBox(width: 8),
                          _CountBadge(
                              count: group.activeCount, color: Colors.green),
                        ],
                        if (group.closedCount > 0) ...[
                          const SizedBox(width: 5),
                          _CountBadge(count: group.closedCount, color: muted),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '↑ ${TrafficValue(value: group.upload.toInt()).show}  '
                      '↓ ${TrafficValue(value: group.download.toInt()).show}',
                      style:
                          context.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '↑ ${connectionRate(group.uploadSpeed)}  '
                      '↓ ${connectionRate(group.downloadSpeed)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: group.uploadSpeed + group.downloadSpeed > 0
                            ? context.colorScheme.primary
                            : muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$count',
          style: context.textTheme.labelSmall?.copyWith(color: Colors.white),
        ),
      );
}

class TrackedConnectionRow extends StatelessWidget {
  const TrackedConnectionRow({
    super.key,
    required this.item,
    required this.showIcon,
    required this.useApplicationName,
    this.onTap,
    this.onClose,
  });

  final TrackedConnection item;
  final bool showIcon;
  final bool useApplicationName;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final connection = item.connection;
    final metadata = connection.metadata;
    final process = connectionProcessName(
      metadata,
      applicationName: useApplicationName,
    );
    final muted = context.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: kConnRowExtent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              ProcessIcon(
                process: metadata.process,
                processPath: metadata.processPath,
                connectionType: metadata.type,
                enabled: showIcon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            process,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('→', style: TextStyle(color: muted)),
                        ),
                        Expanded(
                          child: Text(
                            connectionDestination(connection),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '↑ ${connectionRate(item.uploadSpeed)}  '
                      '↓ ${connectionRate(item.downloadSpeed)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: item.uploadSpeed + item.downloadSpeed > 0
                            ? context.colorScheme.primary
                            : muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${metadata.network.toUpperCase()}  ·  '
                      '${connection.chains.join(' → ')}  ·  '
                      '↑ ${TrafficValue(value: connection.upload?.toInt()).show}  '
                      '↓ ${TrafficValue(value: connection.download?.toInt()).show}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          context.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: Icon(
                    item.isActive
                        ? Icons.link_off_rounded
                        : Icons.delete_outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Request journal row retained separately from the sampled active/closed store.
class ConnectionRow extends StatelessWidget {
  const ConnectionRow({super.key, required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context) => TrackedConnectionRow(
        item: TrackedConnection(
          connection: connection,
          isActive: false,
          uploadSpeed: 0,
          downloadSpeed: 0,
        ),
        showIcon: true,
        useApplicationName: false,
      );
}
