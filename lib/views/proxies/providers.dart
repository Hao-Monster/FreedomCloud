import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/models/core.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef UpdatingMap = Map<String, bool>;

class ProvidersView extends ConsumerStatefulWidget {

  const ProvidersView({
    super.key,
  });

  @override
  ConsumerState<ProvidersView> createState() => _ProvidersViewState();
}

class _ProvidersViewState extends ConsumerState<ProvidersView> {

  Future<String?> _refreshProvider(ExternalProvider provider) async {
    final notifier = ref.read(providersProvider.notifier);
    notifier.setProvider(provider.copyWith(isUpdating: true));
    String? message;
    try {
      message = await clashCore.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) {
        return "${provider.name}: $message \n";
      }
    } catch (error) {
      return "${provider.name}: $error \n";
    } finally {
      try {
        final refreshed = await clashCore.getExternalProvider(provider.name);
        notifier.setProvider(refreshed ?? provider.copyWith(isUpdating: false));
      } catch (_) {
        notifier.setProvider(provider.copyWith(isUpdating: false));
      }
    }
    return message?.isNotEmpty == true ? "${provider.name}: $message \n" : null;
  }

  Future<void> _updateProviders() async {
    final providers = ref.read(providersProvider);
    final messages = [];
    final updateProviders = providers.map(_refreshProvider);
    final results = await Future.wait(updateProviders);
    messages.addAll(results.whereType<String>());
    final titleMedium = context.textTheme.titleMedium;
    globalState.appController.updateGroupsDebounce();
    if (messages.isNotEmpty) {
      globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(
          children: [
            for (final message in messages)
              TextSpan(
                text: message,
                style: titleMedium,
              )
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(providersProvider);
    final proxyProviders = providers.where((item) => item.type == "Proxy").map(
          (item) => ProviderItem(
            provider: item,
          ),
        );
    final ruleProviders = providers.where((item) => item.type == "Rule").map(
          (item) => ProviderItem(
            provider: item,
          ),
        );
    final proxySection = generateSection(
      title: appLocalizations.proxyProviders,
      items: proxyProviders,
    );
    final ruleSection = generateSection(
      title: appLocalizations.ruleProviders,
      items: ruleProviders,
    );
    return CommonScaffold(
      actions: [
        IconButton(
          onPressed: _updateProviders,
          icon: const Icon(
            Icons.sync,
          ),
        )
      ],
      body: generateListView([
        ...proxySection,
        ...ruleSection,
      ]),
      title: appLocalizations.providers,
    );
  }
}

class ProviderItem extends StatelessWidget {

  const ProviderItem({
    super.key,
    required this.provider,
  });
  final ExternalProvider provider;

  Future<void> _handleUpdateProvider() async {
    final appController = globalState.appController;
    if (provider.vehicleType != "HTTP") return;
    var message = '';
    try {
      appController.setProvider(provider.copyWith(isUpdating: true));
      message = await clashCore.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) throw message;
    } catch (error) {
      globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(text: '${provider.name}: $error'),
      );
    } finally {
      try {
        appController.setProvider(
          await clashCore.getExternalProvider(provider.name) ??
              provider.copyWith(isUpdating: false),
        );
      } catch (_) {
        appController.setProvider(provider.copyWith(isUpdating: false));
      }
    }
    globalState.appController.updateGroupsDebounce();
  }

  String _buildProviderDesc() {
    final baseInfo = provider.updateAt.lastUpdateTimeDesc;
    final count = provider.count;
    return switch (count == 0) {
      true => baseInfo,
      false => "$baseInfo  ·  $count${appLocalizations.entries}",
    };
  }

  @override
  Widget build(BuildContext context) => ListItem(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      title: Text(provider.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            height: 4,
          ),
          Text(
            _buildProviderDesc(),
          ),
          const SizedBox(
            height: 4,
          ),
          if (provider.subscriptionInfo != null)
            SubscriptionInfoView(
              subscriptionInfo: provider.subscriptionInfo,
            ),
          const SizedBox(
            height: 8,
          ),
          Wrap(
            runSpacing: 6,
            spacing: 12,
            children: [
              if (provider.vehicleType == "HTTP")
                CommonChip(
                  avatar: const Icon(Icons.sync),
                  label: appLocalizations.sync,
                  onPressed: _handleUpdateProvider,
                ),
            ],
          ),
          const SizedBox(
            height: 4,
          ),
        ],
      ),
      trailing: SizedBox(
        height: 48,
        width: 48,
        child: FadeThroughBox(
          child: provider.isUpdating
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                )
              : const SizedBox(),
        ),
      ),
    );
}
