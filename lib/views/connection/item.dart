import 'dart:io';

import 'package:flclashx/clash/agent_protocol.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/process_icon.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/plugins/app.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

const double kConnRowExtent = 88;

final _androidProcessIconCache =
    BoundedCache<String, Future<ImageProvider?>?>(maxEntries: 64);

Future<String?> showApplicationProxyGroupDialog(
  BuildContext context, {
  String? selectedGroup,
}) async {
  final groups = availablePerAppTargetGroups(
    globalState.proxyGroupOrder.value,
  );
  if (groups.length == 1) return groups.single;
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(appLocalizations.proxyGroup),
      children: [
        for (final group in groups)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, group),
            child: Row(
              children: [
                if (group == selectedGroup)
                  const Icon(Icons.check_rounded, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

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
  return formatConnectionAddress(host, metadata.destinationPort);
}

/// Formats an endpoint without making IPv6 addresses ambiguous.
///
/// Mihomo may return either a host name, an IPv4 address, or an IPv6 literal
/// for the same metadata field. Bracketing IPv6 literals is required whenever
/// a port is appended, otherwise `2001:db8::1:443` cannot be parsed back into
/// an address and port by users or diagnostics tooling.
String formatConnectionAddress(String host, String port) {
  if (host.isEmpty) return '';
  if (port.isEmpty) return host;
  final isBracketed = host.startsWith('[') && host.endsWith(']');
  final isIpv6 = host.contains(':') && !isBracketed;
  return isIpv6 ? '[$host]:$port' : '$host:$port';
}

String connectionRate(double value) =>
    '${TrafficValue(value: value.round()).show}/s';

/// User-facing rendering for the strict-capture status reported by Agent.
///
/// A missing status is deliberately shown as *unreported* rather than
/// inventing an armed/failed state.  The Agent status is the only authority
/// for capture readiness; the connection UI must not claim that a policy is
/// enforced until that status is received.
String strictPolicyStateLabel(AgentStrictPolicyState state) =>
    state.name.replaceAll('_', ' ').toUpperCase();

String strictPolicyFailureLabel(AgentStrictPolicyFailureReason reason) =>
    reason.name
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (match) {
          return '${match.group(1)} ${match.group(2)}';
        })
        .toUpperCase();

class StrictPolicyStatusIndicator extends StatelessWidget {
  const StrictPolicyStatusIndicator(
      {super.key, this.status, this.compact = false});

  final AgentStrictPolicyStatus? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = status?.state;
    final color = switch (state) {
      AgentStrictPolicyState.armed => Colors.green,
      AgentStrictPolicyState.blocking => context.colorScheme.error,
      AgentStrictPolicyState.degraded ||
      AgentStrictPolicyState.preparing =>
        Colors.orange,
      AgentStrictPolicyState.recovering => context.colorScheme.primary,
      AgentStrictPolicyState.disabled ||
      null =>
        context.colorScheme.onSurfaceVariant,
    };
    final label = status == null
        ? 'STRICT STATUS UNREPORTED'
        : [
            strictPolicyStateLabel(status!.state),
            if (status!.failureReason != null)
              strictPolicyFailureLabel(status!.failureReason!),
          ].join(' · ');
    final tooltip = status == null
        ? 'Agent has not reported strict-capture status'
        : 'generation ${status!.generation} · '
            '${status!.failClosed ? 'fail-closed' : 'forwarding allowed'}';
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status?.failClosed == true
                  ? Icons.block_rounded
                  : status?.state == AgentStrictPolicyState.armed
                      ? Icons.verified_rounded
                      : Icons.help_outline_rounded,
              size: compact ? 12 : 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sorts process overview cards using the same setting as the classic list.
///
/// The tracker keeps groups in its own activity order, which is useful as a
/// fallback but made the connection sort setting appear ineffective while in
/// process mode. Values are materialized once per group so rebuilds do not
/// repeatedly walk every connection during comparator calls.
List<ProcessConnectionGroup> sortProcessConnectionGroups(
  Iterable<ProcessConnectionGroup> groups,
  ConnectionSort sort, {
  ConnectionSortDirection? direction,
}) {
  final resolvedDirection = direction ??
      (sort == ConnectionSort.process
          ? ConnectionSortDirection.ascending
          : ConnectionSortDirection.descending);
  final entries = groups
      .map(
        (group) => MapEntry<ProcessConnectionGroup, Object>(
          group,
          _processGroupSortValue(group, sort),
        ),
      )
      .toList(growable: false);
  final sorted = List<MapEntry<ProcessConnectionGroup, Object>>.of(entries)
    ..sort((left, right) {
      final comparison = _compareSortValues(left.value, right.value);
      final directed = resolvedDirection == ConnectionSortDirection.ascending
          ? comparison
          : -comparison;
      if (directed != 0) return directed;
      return left.key.key.toLowerCase().compareTo(right.key.key.toLowerCase());
    });
  return sorted.map((entry) => entry.key).toList(growable: false);
}

Object _processGroupSortValue(
        ProcessConnectionGroup group, ConnectionSort sort) =>
    switch (sort) {
      ConnectionSort.time => _latestProcessConnectionStart(group),
      ConnectionSort.upload => group.upload,
      ConnectionSort.download => group.download,
      ConnectionSort.uploadSpeed => group.uploadSpeed,
      ConnectionSort.downloadSpeed => group.downloadSpeed,
      ConnectionSort.process => connectionProcessName(
          (group.activeConnections.firstOrNull?.connection ??
                  group.closedConnections.first.connection)
              .metadata,
        ).toLowerCase(),
    };

DateTime _latestProcessConnectionStart(ProcessConnectionGroup group) {
  var latest = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
  for (final item in group.activeConnections) {
    if (item.connection.start.isAfter(latest)) latest = item.connection.start;
  }
  for (final item in group.closedConnections) {
    if (item.connection.start.isAfter(latest)) latest = item.connection.start;
  }
  return latest;
}

int _compareSortValues(Object left, Object right) {
  if (left is num && right is num) return left.compareTo(right);
  if (left is DateTime && right is DateTime) return left.compareTo(right);
  return left.toString().compareTo(right.toString());
}

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
    this.policy = ApplicationRoutingPolicy.inherit,
    this.policyTargetGroup,
    this.onPolicyChanged,
    this.strictStatus,
  });

  final ProcessConnectionGroup group;
  final bool showIcon;
  final bool useApplicationName;
  final VoidCallback onTap;
  final ApplicationRoutingPolicy policy;
  final String? policyTargetGroup;
  final ValueChanged<ApplicationRoutingPolicy>? onPolicyChanged;

  /// Latest status received from Agent for this app's strict policy.  Null
  /// means no status has been reported and is shown explicitly in the UI.
  final AgentStrictPolicyStatus? strictStatus;

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
                    if (policy != ApplicationRoutingPolicy.inherit) ...[
                      const SizedBox(height: 4),
                      StrictPolicyStatusIndicator(
                        status: strictStatus,
                        compact: true,
                      ),
                    ],
                  ],
                ),
              ),
              if (onPolicyChanged != null)
                PopupMenuButton<ApplicationRoutingPolicy>(
                  initialValue: policy,
                  tooltip: policy == ApplicationRoutingPolicy.proxy
                      ? 'PROCESS-PATH · ${policyTargetGroup ?? 'GLOBAL'}'
                      : 'PROCESS-PATH',
                  onSelected: onPolicyChanged,
                  icon: Icon(
                    Icons.route_outlined,
                    color: policy == ApplicationRoutingPolicy.inherit
                        ? muted
                        : context.colorScheme.primary,
                  ),
                  itemBuilder: (_) => ApplicationRoutingPolicy.values
                      .map(
                        (value) => PopupMenuItem(
                          value: value,
                          child: Row(
                            children: [
                              if (value == policy)
                                const Icon(Icons.check_rounded, size: 18)
                              else
                                const SizedBox(width: 18),
                              const SizedBox(width: 8),
                              Text(
                                value == ApplicationRoutingPolicy.proxy
                                    ? 'PROXY · ${policyTargetGroup ?? 'GLOBAL'}'
                                    : applicationRoutingPolicyLabel(value),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
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
