import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../design_system/tokens.dart';

/// Library — personal archive with search (spec §9.2).
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text;
    final items = query.trim().isEmpty
        ? ref.watch(itemsProvider)
        : ref.watch(searchProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('Library'), actions: [IconButton(tooltip: 'Recall / Memory Assistant', onPressed: () => context.push('/recall'), icon: const Icon(Icons.travel_explore)), IconButton(tooltip: 'Smart Memory', onPressed: () => context.push('/memory'), icon: const Icon(Icons.hub_outlined))]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search your content…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: items.when(
              data: (list) => list.isEmpty
                  ? const Center(
                      child: Text('No results', style: TextStyle(color: RefractColors.muted)),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) => _LibraryTile(item: list[i]),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/import'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Inline library tab used inside Home's bottom navigation.
class LibraryTabInline extends StatelessWidget {
  const LibraryTabInline({super.key});

  @override
  Widget build(BuildContext context) => const LibraryPage();
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(item.sourceType)),
      title: Text(item.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${sourceTypeLabel(item.sourceType)} · confidence ${(item.extractionConfidence * 100).toStringAsFixed(0)}%',
        maxLines: 1,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/reader/${item.id}'),
    );
  }

  IconData _iconFor(SourceType t) => switch (t) {
        SourceType.pdf => Icons.picture_as_pdf_outlined,
        SourceType.url => Icons.link,
        SourceType.html => Icons.web_outlined,
        _ => Icons.article_outlined,
      };
}
