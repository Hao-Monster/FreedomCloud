import 'package:flclashx/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PurchaseView extends StatelessWidget {
  const PurchaseView({super.key});

  static const _wechatAccounts = [
    'ChasingDream_2021',
    'dxm_qa',
  ];

  Future<void> _copyWechat(BuildContext context, String account) async {
    await Clipboard.setData(ClipboardData(text: account));
    if (context.mounted) {
      await context.showNotifier(appLocalizations.copySuccess);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: context.colorScheme.primaryContainer,
                  foregroundColor: context.colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.shopping_bag_rounded, size: 34),
                ),
                const SizedBox(height: 20),
                Text(
                  appLocalizations.purchaseTitle,
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  appLocalizations.purchaseContactDescription,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                for (final account in _wechatAccounts) ...[
                  _WechatAccountCard(
                    account: account,
                    onCopy: () => _copyWechat(context, account),
                  ),
                  if (account != _wechatAccounts.last)
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      );
}

class _WechatAccountCard extends StatelessWidget {
  const _WechatAccountCard({
    required this.account,
    required this.onCopy,
  });

  final String account;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: context.colorScheme.secondaryContainer,
                foregroundColor: context.colorScheme.onSecondaryContainer,
                child: const Icon(Icons.chat_bubble_rounded),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appLocalizations.wechatId,
                      style: context.textTheme.labelLarge?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      account,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(appLocalizations.copy),
              ),
            ],
          ),
        ),
      );
}
