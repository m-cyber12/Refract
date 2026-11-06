import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../design_system/tokens.dart';

/// Reader — Clean Reader mode with provenance panel (spec §9.3).
class ReaderPage extends ConsumerWidget {
  const ReaderPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemProvider(itemId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader'),
        actions: [
          itemAsync.value != null
              ? IconButton(
                  icon: const Icon(Icons.label_outline),
                  onPressed: () => _showAddTag(context, ref, itemAsync.value!.id),
                )
              : const SizedBox.shrink(),
        ],
      ),
      body: itemAsync.when(
        data: (item) {
          if (item == null) {
            return const Center(child: Text('Item not found'));
          }
          return _ReaderView(item: item);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: itemAsync.value != null
          ? FloatingActionButton.extended(
              onPressed: () => _showAddAnnotation(context, ref, itemAsync.value!.id),
              icon: const Icon(Icons.edit_note),
              label: const Text('Note'),
            )
          : null,
    );
  }

  Future<void> _showAddTag(BuildContext context, WidgetRef ref, String itemId) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add tag'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Tag name'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final repo = await ref.read(bootstrapProvider.future);
              repo.tagItem(itemId, name);
              ref.invalidate(tagsProvider);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddAnnotation(BuildContext context, WidgetRef ref, String itemId) async {
    final quoteController = TextEditingController();
    final noteController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: quoteController, decoration: const InputDecoration(labelText: 'Quoted text')),
            const SizedBox(height: 8),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Your note')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final repo = await ref.read(bootstrapProvider.future);
              repo.addAnnotation(itemId, quoteController.text, note: noteController.text.isEmpty ? null : noteController.text);
              ref.invalidate(annotationsProvider(itemId));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ReaderView extends StatelessWidget {
  const _ReaderView({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        if (item.title != null)
          Text(item.title!, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _Provenance(item: item),
        const Divider(height: 32),
        const _IntelligenceSection(),
        const Divider(height: 32),
        for (final block in item.blocks) _BlockView(block: block),
        const Divider(height: 32),
        _AnnotationsSection(itemId: item.id),
        const Divider(height: 32),
        _RelatedSection(itemId: item.id),
      ],
    );
  }
}

/// Local intelligence panel: labeled summary + suggested tags (spec §5.3, §3.5).
/// Output kind is always shown so interpretations are never mistaken for fact.
class _IntelligenceSection extends ConsumerWidget {
  const _IntelligenceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemId = (context.findAncestorWidgetOfExactType<_ReaderView>() as _ReaderView).item.id;
    final summary = ref.watch(summaryProvider(itemId));
    final tags = ref.watch(suggestedTagsProvider(itemId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: RefractColors.spectralViolet),
            const SizedBox(width: 8),
            Text('Briefing', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        summary.when(
          data: (s) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: RefractColors.elevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: RefractColors.spectralViolet.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['text'] as String, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                Text(
                  '${s['kind']} output · model: ${s['model_used'] == true ? 'local' : 'none (deterministic)'} · sources: blocks ${(s['source_blocks'] as List).join(', ')}',
                  style: const TextStyle(fontSize: 11, color: RefractColors.muted, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Summary unavailable: $e', style: const TextStyle(color: RefractColors.muted)),
        ),
        const SizedBox(height: 8),
        tags.when(
          data: (t) => Wrap(
            spacing: 6,
            children: [
              for (final tag in (t['text'] as String).split(', '))
                ActionChip(
                  label: Text(tag),
                  onPressed: () async {
                    final repo = await ref.read(bootstrapProvider.future);
                    repo.tagItem(itemId, tag);
                    ref.invalidate(tagsProvider);
                  },
                ),
            ],
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _RelatedSection extends ConsumerWidget {
  const _RelatedSection({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(relatedProvider(itemId));
    return related.when(
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Related', style: Theme.of(context).textTheme.titleMedium),
                for (final r in list)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.link, size: 18),
                    title: Text(r.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => context.push('/reader/${r.id}'),
                  ),
              ],
            ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

Future<void> _shareAnnotation(BuildContext context, WidgetRef ref, Annotation a) async {
  final repo = await ref.read(bootstrapProvider.future);
  final workspaces = repo.listWorkspaces();
  if (!context.mounted) return;
  String? chosen;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Share annotation'),
      content: workspaces.isEmpty
          ? const Text('No workspaces yet. Only the annotation is shared — never the source document.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [for (final w in workspaces) ListTile(title: Text(w[1]), onTap: () { chosen = w[0]; Navigator.pop(dialogContext); })],
            ),
      actions: [
        if (workspaces.isEmpty)
          FilledButton(
            onPressed: () {
              chosen = repo.createWorkspace('Shared notes');
              Navigator.pop(dialogContext);
            },
            child: const Text('Create workspace'),
          ),
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
      ],
    ),
  );
  if (chosen == null) return;
  repo.shareAnnotation(chosen!, a.id, {'quote': a.quote, 'note': a.note, 'itemId': a.itemId, 'visibility': 'shared'});
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annotation queued for sync')));
  }
}

class _AnnotationsSection extends ConsumerWidget {
  const _AnnotationsSection({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotations = ref.watch(annotationsProvider(itemId));
    return annotations.when(
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Annotations', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (list.isEmpty)
            const Text('No notes yet.', style: TextStyle(color: RefractColors.muted))
          else
            for (final a in list)
              ListTile(
                dense: true,
                leading: const Icon(Icons.format_quote, size: 18),
                title: Text(a.quote, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: a.note != null ? Text(a.note!) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.ios_share_outlined, size: 18),
                  tooltip: 'Share to workspace',
                  onPressed: () => _shareAnnotation(context, ref, a),
                ),
              ),
        ],
      ),
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
    );
  }
}

class _Provenance extends StatelessWidget {
  const _Provenance({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RefractColors.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: RefractColors.muted, fontSize: 12, fontFamily: 'monospace'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.sourceUrl != null) Text('source  ${item.sourceUrl}', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('hash    ${item.contentHash.substring(0, 16)}…'),
            Text('confidence  ${(item.extractionConfidence * 100).toStringAsFixed(0)}%'),
          ],
        ),
      ),
    );
  }

}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});
  final Block block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (block.kind) {
      case BlockKind.heading1:
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(block.text, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        );
      case BlockKind.heading2:
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(block.text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        );
      case BlockKind.heading3:
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(block.text, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        );
      case BlockKind.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: RefractColors.spectralViolet, width: 3)),
          ),
          child: Text(block.text, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
        );
      case BlockKind.listItem:
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: Text(block.text, style: theme.textTheme.bodyLarge)),
            ],
          ),
        );
      case BlockKind.code:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: RefractColors.graphite,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(block.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        );
      case BlockKind.image:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [const Icon(Icons.image_outlined, size: 18), const SizedBox(width: 8), Expanded(child: Text(block.text))]),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(block.text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
        );
    }
  }
}
