import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/share_intent.dart';

class SharedDraftsPage extends StatelessWidget {
  const SharedDraftsPage({super.key, this.inbox});
  final ShareIntentChannel? inbox;
  Future<void> _discard(BuildContext context, ShareIntentChannel shares, SharedDraft draft) async {
    if (draft.staged) {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Delete this staged handoff copy?'),
        content: const Text('This removes the iOS handoff copy, or an unreadable handoff batch if indicated. Library originals and approved capture jobs are not deleted. Open editors can still hold copies. This is not secure erasure of memory, backups or provider caches.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep copy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete handoff copy'))]));
      if (confirmed != true) return;
    }
    await shares.remove(draft.id);
  }
  @override Widget build(BuildContext context) {
    final shares = inbox ?? ShareIntentChannel.instance;
    return Scaffold(appBar: AppBar(title: const Text('Shared drafts'), actions: [
      IconButton(tooltip: 'Check native handoff', onPressed: shares.pull, icon: const Icon(Icons.refresh)),
    ]), body: AnimatedBuilder(animation: shares, builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Temporary input only: no automatic preview, save or URL fetch. Review each item separately. Opening this inbox never writes to the library.'),
      const Text('Android shares are held in process memory (16 entries / 24 MiB per native or Dart inbox). They can be lost on process death. File providers may download/cache the files you share. Discard removes the inbox entry; open editors can still hold copies. It is not secure erasure of memory or provider caches.'),
      if (shares.drafts.any((d) => d.staged)) const Text('iOS: explicitly consented handoff copies remain in the shared app container without app-level encryption until saved or explicitly discarded. Receiving a copy here does not delete it. There is no automatic expiry. A save completed through job recovery can leave a redundant handoff copy; open the existing library copy or discard it explicitly.'),
      if (shares.notice != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text(shares.notice!), TextButton(onPressed: shares.clearNotice, child: const Text('Dismiss notice')),
      ]))),
      if (shares.drafts.isEmpty) const Text('No shared drafts waiting.'),
      for (final draft in shares.drafts) Card(key: ValueKey(draft.id), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(draft.file?.name ?? 'Share could not be accepted'),
        if (draft.file != null) Text('${draft.file!.format} · ${draft.byteLength} bytes · not saved'),
        if (draft.staged) const Text('Staged on iOS · retained until save/discard · not a library original'),
        if (draft.consentTS != null) Text('Handoff consent on this device: ${DateTime.fromMillisecondsSinceEpoch(draft.consentTS! * 1000, isUtc: true).toIso8601String()} (not source publication or library import time)'),
        if (draft.error != null) Text(draft.error!),
        Wrap(spacing: 8, children: [
          if (draft.file != null) FilledButton(onPressed: () => context.push('/import', extra: draft), child: const Text('Review this draft')),
          TextButton(onPressed: () => _discard(context, shares, draft), child: const Text('Discard draft')),
        ]),
      ]))),
    ])));
  }
}
