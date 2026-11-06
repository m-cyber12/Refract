import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../design_system/tokens.dart';

/// Vault — append-only evidence with hashes and "what this proves" (spec §9.5).
class VaultPage extends ConsumerStatefulWidget {
  const VaultPage({super.key});

  @override
  ConsumerState<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends ConsumerState<VaultPage> {
  final Map<String, bool?> _verification = {};

  Future<void> _verify(EvidenceRecord rec) async {
    final repo = await ref.read(bootstrapProvider.future);
    setState(() => _verification[rec.id] = repo.verifyEvidence(rec.id));
  }

  Future<void> _importReceipt() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import receipt / terms text'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Paste receipt or policy text…',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              final repo = await ref.read(bootstrapProvider.future);
              repo.addEvidence('receipt', null, text.codeUnits, textForClaims: text);
              ref.invalidate(evidenceProvider);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Store evidence'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final evidence = ref.watch(evidenceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Proof Vault')),
      body: evidence.when(
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No evidence yet. Receipts and contracts you import are stored locally, hashed, and never altered.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: RefractColors.muted),
                  ),
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => _EvidenceTile(
                  record: list[i],
                  verified: _verification[list[i].id],
                  onVerify: () => _verify(list[i]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importReceipt,
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Import evidence'),
      ),
    );
  }
}

class _EvidenceTile extends ConsumerWidget {
  const _EvidenceTile({required this.record, required this.onVerify, this.verified});
  final EvidenceRecord record;
  final VoidCallback onVerify;
  final bool? verified;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(claimsProvider(record.id));
    return ExpansionTile(
      leading: const Icon(Icons.verified_user_outlined),
      title: Text(record.note ?? record.kind),
      subtitle: Text(
        '${record.kind} · sha256 ${record.sha256.substring(0, 12)}…',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
      trailing: verified == null
          ? IconButton(icon: const Icon(Icons.fact_check_outlined), onPressed: onVerify)
          : Icon(Icons.check_circle,
              color: verified == true ? RefractColors.verificationGreen : RefractColors.signalAmber),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              verified == true
                  ? 'Hash matches — file unchanged since import. (This proves integrity, not origin authenticity.)'
                  : verified == false
                      ? 'HASH MISMATCH — file changed since import!'
                      : 'Not verified yet.',
              style: TextStyle(
                fontSize: 12,
                color: verified == false ? RefractColors.signalAmber : RefractColors.muted,
              ),
            ),
          ),
        ),
        claims.when(
          data: (list) => Column(
            children: [for (final c in list.take(10)) _ClaimTile(claim: c)],
          ),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
      ],
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.claim});
  final EvidenceClaim claim;

  @override
  Widget build(BuildContext context) {
    final color = switch (claim.claimType) {
      'quote' => RefractColors.prismCyan,
      'extracted' => RefractColors.spectralViolet,
      _ => RefractColors.signalAmber,
    };
    return ListTile(
      dense: true,
      leading: Icon(Icons.label, size: 16, color: color),
      title: Text(claim.text, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${claim.claimType} · ${(claim.confidence * 100).toStringAsFixed(0)}%'),
    );
  }
}
