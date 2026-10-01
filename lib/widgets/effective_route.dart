import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/views/proxies/card.dart';
import 'package:flclashx/views/proxies/common.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A connection supplies its observed chain; a policy supplies its target.
/// Keeping them distinct avoids claiming a historic flow used today's node.
class EffectiveRouteButton extends StatelessWidget {
  const EffectiveRouteButton({super.key, required this.chains, this.policy = false});

  final List<String> chains;
  final bool policy;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: appLocalizations.connectionsRouting,
        icon: const Icon(Icons.alt_route_rounded),
        onPressed: chains.isEmpty
            ? null
            : () => showExtend(
                  context,
                  props: const ExtendProps(maxWidth: 560),
                  builder: (_, type) => AdaptiveSheetScaffold(
                    type: type,
                    title: appLocalizations.connectionsRouting,
                    body: _EffectiveRoute(chains: chains, policy: policy),
                  ),
                ),
      );
}

class _EffectiveRoute extends ConsumerWidget {
  const _EffectiveRoute({required this.chains, required this.policy});

  final List<String> chains;
  final bool policy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final selected = ref.watch(selectedMapProvider);
    final names = <String>[];
    if (policy) {
      // Resolve bounded nested groups without looping on malformed profiles.
      var name = chains.first;
      for (var depth = 0; depth < 32 && name.isNotEmpty && !names.contains(name); depth++) {
        names.add(name);
        final group = groups.getGroup(name);
        if (group == null) break;
        name = group.getCurrentSelectedName(selected[name] ?? '');
      }
    } else {
      names.addAll(chains.toSet());
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: names.length,
      itemBuilder: (context, index) {
        final name = names[index];
        final group = groups.getGroup(name);
        if (group == null) {
          final known = name == 'DIRECT' || name == 'REJECT' ||
              groups.any((group) => group.all.any((proxy) => proxy.name == name));
          return ListTile(
            leading: Icon(known ? Icons.dns_outlined : Icons.help_outline),
            title: SelectableText(name),
            subtitle: Text(known ? appLocalizations.proxies : appLocalizations.noData),
          );
        }
        final active = group.getCurrentSelectedName(selected[name] ?? '');
        final proxies = [...group.all];
        // Put the observed hop first for connections, or the current hop for
        // policies; keep all other nodes available in the same focused group.
        final focus = policy ? active : chains.firstWhere(
          (hop) => group.all.any((proxy) => proxy.name == hop),
          orElse: () => active,
        );
        final focusIndex = proxies.indexWhere((proxy) => proxy.name == focus);
        if (focusIndex > 0) proxies.insert(0, proxies.removeAt(focusIndex));
        return Card(
          child: ExpansionTile(
            key: ValueKey(name),
            initiallyExpanded: true,
            title: Text(name),
            subtitle: Text('${appLocalizations.proxies}: $active'),
            children: [
              SizedBox(
                height: 320,
                child: ListView.builder(
                  itemCount: proxies.length,
                  itemExtent: getItemHeight(ProxyCardType.expand),
                  itemBuilder: (context, index) => ProxyCard(
                    groupName: group.name,
                    testUrl: group.testUrl,
                    proxy: proxies[index],
                    groupType: group.type,
                    type: ProxyCardType.expand,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
