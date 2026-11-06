import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/repository.dart';

/// Import — paste text, share a URL reference, or paste raw HTML (spec §A1).
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final uri = Uri.tryParse(text);
      final isUrl = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
      final looksLikeHtml = text.contains('<') && text.contains('>');
      final item = looksLikeHtml
          ? repo.importHtml(text, sourceUrl: isUrl ? text : null)
          : repo.importText(text, sourceUrl: isUrl ? text : null);
      ref.invalidate(itemsProvider);
      if (mounted) context.go('/reader/${item.id}');
    } on Exception catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Paste a URL, text, Markdown or HTML…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_outlined),
              label: const Text('Refract into library'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
