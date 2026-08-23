import 'dart:async';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'item.dart';

void showConnectionDetail(
  BuildContext context,
  TrackedConnection item, {
  VoidCallback? onClose,
}) {
  unawaited(
    showExtend(
      context,
      props: const ExtendProps(maxWidth: 480),
      builder: (_, type) => AdaptiveSheetScaffold(
        type: type,
        title: appLocalizations.connectionsDetail,
        actions: [
          if (onClose != null)
            IconButton(
              onPressed: () {
                unawaited(Navigator.of(context).maybePop());
                onClose();
              },
              icon: const Icon(Icons.link_off_rounded),
            ),
        ],
        body: _ConnectionDetailBody(item: item),
      ),
    ),
  );
}

class _ConnectionDetailBody extends StatelessWidget {
  const _ConnectionDetailBody({required this.item});

  final TrackedConnection item;

  @override
  Widget build(BuildContext context) {
    final connection = item.connection;
    final metadata = connection.metadata;
    final sections = <_DetailSection>[
      _DetailSection(
        appLocalizations.connectionsTraffic,
        [
          _DetailValue(appLocalizations.connectionsUploadSpeed,
              connectionRate(item.uploadSpeed)),
          _DetailValue(appLocalizations.connectionsDownloadSpeed,
              connectionRate(item.downloadSpeed)),
          _DetailValue(
            appLocalizations.connectionsTotalUpload,
            TrafficValue(value: connection.upload?.toInt()).show,
          ),
          _DetailValue(
            appLocalizations.connectionsTotalDownload,
            TrafficValue(value: connection.download?.toInt()).show,
          ),
        ],
      ),
      _DetailSection(
        appLocalizations.connectionsRouting,
        [
          _DetailValue(appLocalizations.connectionsRule, connection.rule),
          _DetailValue(
              appLocalizations.connectionsRulePayload, connection.rulePayload),
          _DetailValue(
            appLocalizations.connectionsProxyChain,
            connection.chains.join(' → '),
          ),
          _DetailValue(appLocalizations.connectionsRemoteDestination,
              metadata.remoteDestination),
        ],
      ),
      _DetailSection(
        appLocalizations.network,
        [
          _DetailValue(appLocalizations.connectionsType, metadata.type),
          _DetailValue(
              appLocalizations.network, metadata.network.toUpperCase()),
          _DetailValue(appLocalizations.connectionsHost, metadata.host),
          _DetailValue(
              appLocalizations.connectionsSniffHost, metadata.sniffHost),
          _DetailValue(
            appLocalizations.connectionsSource,
            _address(metadata.sourceIP, metadata.sourcePort),
          ),
          _DetailValue(
            appLocalizations.connectionsDestination,
            _address(metadata.destinationIP, metadata.destinationPort),
          ),
          _DetailValue(appLocalizations.connectionsDnsMode, metadata.dnsMode),
          _DetailValue(appLocalizations.connectionsSourceGeo,
              metadata.sourceGeoIP.join(' · ')),
          _DetailValue(
            appLocalizations.connectionsDestinationGeo,
            metadata.destinationGeoIP.join(' · '),
          ),
        ],
      ),
      _DetailSection(
        appLocalizations.connectionsProcess,
        [
          _DetailValue(appLocalizations.connectionsProcess, metadata.process),
          _DetailValue(
              appLocalizations.connectionsProcessPath, metadata.processPath),
          _DetailValue(appLocalizations.connectionsUid, '${metadata.uid}'),
        ],
      ),
      _DetailSection(
        appLocalizations.connectionsInbound,
        [
          _DetailValue(
              appLocalizations.connectionsInboundName, metadata.inboundName),
          _DetailValue(
              appLocalizations.connectionsInboundUser, metadata.inboundUser),
          _DetailValue(
            appLocalizations.connectionsInbound,
            _address(metadata.inboundIP, metadata.inboundPort),
          ),
        ],
      ),
      _DetailSection(
        appLocalizations.connectionsOther,
        [
          _DetailValue(
              appLocalizations.status,
              item.isActive
                  ? appLocalizations.connectionsActive
                  : appLocalizations.connectionsClosed),
          _DetailValue(appLocalizations.connectionsEstablished,
              connection.start.toLocal().toString()),
          _DetailValue('ID', connection.id),
          _DetailValue('DSCP', '${metadata.dscp}'),
        ],
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: sections
          .where((section) => section.values.any((value) => value.visible))
          .map((section) => _SectionCard(section: section))
          .toList(growable: false),
    );
  }

  static String _address(String ip, String port) {
    if (ip.isEmpty) return '';
    return port.isEmpty ? ip : '$ip:$port';
  }
}

class _DetailSection {
  const _DetailSection(this.title, this.values);

  final String title;
  final List<_DetailValue> values;
}

class _DetailValue {
  const _DetailValue(this.label, this.value);

  final String label;
  final String value;

  bool get visible => value.isNotEmpty && value != '0';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final _DetailSection section;

  @override
  Widget build(BuildContext context) {
    final values = section.values.where((value) => value.visible).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title, style: context.textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final value in values)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(value.label),
                subtitle: SelectableText(value.value),
                trailing: IconButton(
                  tooltip: appLocalizations.copy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: value.value));
                    if (context.mounted) {
                      await context.showNotifier(appLocalizations.copySuccess);
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 19),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
