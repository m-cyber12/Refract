import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../design_system/tokens.dart';

/// X-Ray — subscriptions, upcoming renewals, honest uncertainty (spec §9.4).
class XrayPage extends ConsumerWidget {
  const XrayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider);
    final upcoming = ref.watch(upcomingEventsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('X-Ray'), actions: [IconButton(tooltip: 'Consumer document evidence', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => context.push('/xray/documents'))]),
      body: ListView(
        children: [
          ListTile(leading: const Icon(Icons.receipt_long_outlined), title: const Text('Consumer documents & source comparison'), subtitle: const Text('Receipt totals, subscription terms, renewals, warranties and policies — source-backed candidates, not verified transactions.'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/xray/documents')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Upcoming (30 days)', style: Theme.of(context).textTheme.titleMedium),
          ),
          upcoming.when(
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No renewals or trial deadlines in the next 30 days.',
                        style: TextStyle(color: RefractColors.muted)),
                  )
                : Column(children: [for (final s in list) _SubTile(sub: s, highlight: true)]),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('All subscriptions', style: Theme.of(context).textTheme.titleMedium),
          ),
          subs.when(
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No subscriptions yet. Add one to start tracking renewals.',
                        style: TextStyle(color: RefractColors.muted)),
                  )
                : Column(children: [for (final s in list) _SubTile(sub: s)]),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSubscription(context, ref),
        icon: const Icon(Icons.add_card),
        label: const Text('Add subscription'),
      ),
    );
  }

  Future<void> _showAddSubscription(BuildContext context, WidgetRef ref) async {
    final service = TextEditingController();
    final price = TextEditingController();
    final currency = TextEditingController(text: 'USD');
    final frequency = TextEditingController(text: 'monthly');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: service, decoration: const InputDecoration(labelText: 'Service'), autofocus: true),
            TextField(controller: price, decoration: const InputDecoration(labelText: 'Price'), keyboardType: TextInputType.number),
            TextField(controller: currency, decoration: const InputDecoration(labelText: 'Currency')),
            TextField(controller: frequency, decoration: const InputDecoration(labelText: 'Frequency (monthly/yearly)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final repo = await ref.read(bootstrapProvider.future);
              repo.addSubscription({
                'id': '',
                'service': service.text.trim(),
                'price': double.tryParse(price.text.trim()),
                'currency': currency.text.trim(),
                'frequency': frequency.text.trim(),
                'status': 'confirmed',
                'confidence': 1.0,
                'created_ts': 0,
              });
              ref.invalidate(subscriptionsProvider);
              ref.invalidate(upcomingEventsProvider);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _SubTile extends StatelessWidget {
  const _SubTile({required this.sub, this.highlight = false});
  final Subscription sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (sub.status) {
      SubscriptionStatus.confirmed => RefractColors.verificationGreen,
      SubscriptionStatus.imported => RefractColors.prismCyan,
      SubscriptionStatus.suspected => RefractColors.signalAmber,
      SubscriptionStatus.unverified => RefractColors.muted,
    };
    return ListTile(
      leading: Icon(Icons.subscriptions_outlined, color: highlight ? RefractColors.signalAmber : null),
      title: Text(sub.service),
      subtitle: Text([
        if (sub.price != null) '${sub.price} ${sub.currency ?? ''} ${sub.frequency ?? ''}',
        'status: ${subscriptionStatusLabel(sub.status)} · extraction heuristic ${sub.confidence.toStringAsFixed(2)} (not verification)',
      ].join('\n')),
      trailing: Icon(Icons.circle, size: 10, color: statusColor),
    );
  }
}
