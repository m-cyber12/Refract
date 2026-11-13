import 'original_export.dart';
import 'pdf_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../signal/signal_page.dart';
import '../../design_system/tokens.dart';

/// Reader — Clean Reader mode with provenance panel (spec §9.3).
class ReaderPage extends ConsumerWidget {
  const ReaderPage({super.key, required this.itemId, this.focusBlock});

  final String itemId;
  final int? focusBlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemProvider(itemId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader'),
        actions: [
          IconButton(tooltip:'Source Intelligence',icon:const Icon(Icons.history_edu_outlined),onPressed:()=>context.push('/knowledge/source/${Uri.encodeComponent(itemId)}')),
          IconButton(tooltip: 'Consumer X-Ray evidence', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => context.push('/xray/document/${Uri.encodeComponent(itemId)}')),
          IconButton(tooltip: 'Related sources / Memory Assistant', icon: const Icon(Icons.travel_explore), onPressed: () => context.push('/recall?context=${Uri.encodeComponent(itemId)}')),
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
          return _ReaderView(item: item, focusBlock: focusBlock);
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
          IconButton(tooltip:'Source Intelligence',icon:const Icon(Icons.history_edu_outlined),onPressed:()=>context.push('/knowledge/source/${Uri.encodeComponent(itemId)}')),
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
          IconButton(tooltip:'Source Intelligence',icon:const Icon(Icons.history_edu_outlined),onPressed:()=>context.push('/knowledge/source/${Uri.encodeComponent(itemId)}')),
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

/// Empty blocks do not prove which capture mode was used, particularly for
/// legacy or damaged records. Describe only what the reader can establish.
class PdfReaderNotice extends StatelessWidget {
  const PdfReaderNotice({super.key, required this.hasText});
  final bool hasText;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(hasText ? 'Extracted PDF text' : 'PDF text unavailable', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(hasText
        ? 'PDF reader text may be incomplete: no OCR. Scanned portions, images and layout may be absent. The original is retained separately; signatures and authenticity are not verified.'
        : 'No text blocks are available for this PDF item. Its capture history and PDF validity cannot be determined here. OCR is not available. The original is retained separately; authenticity is not verified.'),
      const Text('Original page layout is available separately on Android after approval.'),
    ]),
  );
}

class _ReaderView extends ConsumerWidget {
  const _ReaderView({required this.item, this.focusBlock});
  final Item item;
  final int? focusBlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        if (focusBlock != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SOURCE / SAVED BLOCK $focusBlock', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (item.blocks.any((b) => b.idx == focusBlock))
            SelectableText(item.blocks.firstWhere((b) => b.idx == focusBlock).text)
          else const Text('This cited block is no longer available. Review the full source below.'),
        ]))),
        if (item.title != null)
          Text(item.title!, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _Provenance(item: item),
        if (item.sourceType == SourceType.urlReference)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Address only. No webpage content, author or publication date was fetched or verified.')),
        if (item.sourceType == SourceType.pdf) PdfLayoutViewer(itemId: item.id),
        if (item.sourceType == SourceType.pdf) PdfReaderNotice(hasText: item.blocks.isNotEmpty),
        if (item.sourceType == SourceType.pdf) OriginalExportButton(itemId: item.id, extension: 'pdf'),
        TextButton.icon(onPressed: () => signalChange(context, ref, (r) => r.saveReadingPlace(item.id, null, 'completed'), message: 'Marked read. Original content unchanged.'), icon: const Icon(Icons.done), label: const Text('Mark read')),
        SignalContextPanel(itemId: item.id),
        const Divider(height: 32),
        const _IntelligenceSection(),
        const Divider(height: 32),
        for (final block in item.blocks) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _BlockView(block: block),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => signalChange(context, ref, (r) => r.saveReadingPlace(item.id, block.idx, 'started'), message: 'Reading place saved at block ${block.idx}.'),
            icon: const Icon(Icons.bookmark_border, size: 16), label: Text('Save place · block ${block.idx}'),
          )),
        ]),
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

Future<void> _shareAnnotation(BuildContext context,WidgetRef ref,Annotation a)async{
 try{final repo=await ref.read(bootstrapProvider.future);final spaces=repo.marginWorkspaces().where((w)=>w.canEdit).toList();if(!context.mounted){return;}
 final chosen=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Review a selected shared copy'),children:[const Padding(padding:EdgeInsets.all(16),child:Text('Choose a workspace, then review the exact quote and optional context. The private annotation and original source remain separate. Nothing is exported automatically.')),...spaces.map((w)=>SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,w.id),child:Text('${w.name} · ${w.role}'))),SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,'create'),child:const Text('Manage / create private workspaces'))]));
 if(chosen!=null&&context.mounted){if(chosen=='create'){context.push('/margins');}else{context.push('/margins/new?workspace=${Uri.encodeComponent(chosen)}&source=${Uri.encodeComponent(a.itemId)}&annotation=${Uri.encodeComponent(a.id)}');}}
 }catch(e){if(context.mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
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
                  tooltip: 'Review sharing with selected devices',
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
