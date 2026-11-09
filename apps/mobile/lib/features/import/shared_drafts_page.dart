import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/share_intent.dart';

class SharedDraftsPage extends StatelessWidget {
  const SharedDraftsPage({super.key, this.inbox});
  final ShareIntentChannel? inbox;
  @override Widget build(BuildContext context) {
    final shares = inbox ?? ShareIntentChannel.instance;
    return Scaffold(appBar: AppBar(title: const Text('Shared drafts'), actions: [
      IconButton(tooltip: 'Check native handoff', onPressed: shares.pull, icon: const Icon(Icons.refresh)),
    ]), body: AnimatedBuilder(animation: shares, builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Temporary input only: no automatic preview, save or URL fetch. Review each item separately. Opening this inbox never writes to the library.'),
      const Text('Android shares are held in process memory (16 entries / 24 MiB per native or Dart inbox). They can be lost on process death. File providers may download/cache the files you share. Discard removes the inbox entry; open editors can still hold copies. It is not secure erasure of memory or provider caches.'),
      if (shares.notice != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text(shares.notice!), TextButton(onPressed: shares.clearNotice, child: const Text('Dismiss notice')),
      ]))),
      if (shares.drafts.isEmpty) const Text('No shared drafts waiting.'),
      for (final draft in shares.drafts) Card(key: ValueKey(draft.id), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(draft.file?.name ?? 'Share could not be accepted'),
        if (draft.file != null) Text('${draft.file!.format} · ${draft.byteLength} bytes · not saved'),
        if (draft.error != null) Text(draft.error!),
        Wrap(spacing: 8, children: [
          if (draft.file != null) FilledButton(onPressed: () => context.push('/import', extra: draft), child: const Text('Review this draft')),
          TextButton(onPressed: () => shares.remove(draft.id), child: const Text('Discard draft')),
        ]),
      ]))),
    ])));
  }
}
