import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/share_intent.dart';
import '../library/library_page.dart';
import '../vault/vault_page.dart';
import '../xray/xray_page.dart';
import '../../design_system/tokens.dart';
import '../../design_system/widgets/prism_mark.dart';

/// Home — personal command center (spec §9.1).
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    // Content shared from other apps lands here and is imported automatically.
    _shareSub = ShareIntentChannel.instance.sharedContent.listen((text) {
      if (!mounted) return;
      final uri = Uri.tryParse(text.trim());
      final isUrl = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
      try {
        final repo = ref.read(bootstrapProvider).value;
        if (repo == null) return;
        // Shared URLs are stored as text references; fetching arrives in a later phase.
        repo.importText(text, sourceUrl: isUrl ? text.trim() : null);
        ref.invalidate(itemsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Imported into your library')),
          );
        }
      } on Exception catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _HomeTab(),
      const LibraryTabInline(),
      const XrayPage(),
      const VaultPage(),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.library_books_outlined), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.visibility_outlined), label: 'X-Ray'),
          NavigationDestination(icon: Icon(Icons.verified_user_outlined), label: 'Vault'),
        ],
      ),
    );
  }
}

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(itemsProvider);
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  const PrismMark(size: 36),
                  const SizedBox(width: 12),
                  Text('REFRACT', style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 4)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: FilledButton.icon(
                onPressed: () => context.push('/import'),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Import content'),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Daily Edition', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
          ),
          _dailyEditionSliver(ref),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(child: Text('Smart Inbox', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: () => context.push('/sense'), child: const Text('Rules')),
              ]),
            ),
          ),
          _smartInboxSliver(ref),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Recently imported', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          items.when(
            data: (list) => list.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nothing here yet. Share an article into REFRACT or import one manually.',
                        style: TextStyle(color: RefractColors.muted),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _ItemTile(item: list[i]),
                      childCount: list.take(10).length,
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(padding: const EdgeInsets.all(20), child: Text('$e')),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _smartInboxSliver(WidgetRef ref) {
  final decisions = ref.watch(senseDecisionsProvider);
  return decisions.when(
    data: (list) {
      final pending = list.where((d) => d.decision == 'smart_suggest' && !d.undone).toList();
      if (pending.isEmpty) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Nothing needs review.', style: TextStyle(color: RefractColors.muted)),
          ),
        );
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final d = pending[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(d.category, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(d.explanation, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                    onPressed: () async {
                      final repo = await ref.read(bootstrapProvider.future);
                      repo.senseReview(d.id, 'approve');
                      ref.invalidate(senseDecisionsProvider);
                    },
                    child: const Text('Save')),
                TextButton(
                    onPressed: () async {
                      final repo = await ref.read(bootstrapProvider.future);
                      repo.senseReview(d.id, 'dismiss');
                      ref.invalidate(senseDecisionsProvider);
                    },
                    child: const Text('Ignore')),
              ]),
            );
          },
          childCount: pending.take(5).length,
        ),
      );
    },
    loading: () => const SliverToBoxAdapter(
      child: Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()),
    ),
    error: (e, _) => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Text('$e'))),
  );
}

Widget _dailyEditionSliver(WidgetRef ref) {
  final edition = ref.watch(dailyEditionProvider);
  return edition.when(
    data: (list) => list.isEmpty
        ? const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Your week at a glance will appear here.', style: TextStyle(color: RefractColors.muted)),
            ),
          )
        : SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ItemTile(item: list[i]),
              childCount: list.take(5).length,
            ),
          ),
    loading: () => const SliverToBoxAdapter(
      child: Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()),
    ),
    error: (e, _) => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Text('$e'))),
  );
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final dynamic item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.article_outlined),
      title: Text(item.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.sourceUrl ?? sourceTypeLabel(item.sourceType), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => context.push('/reader/${item.id}'),
    );
  }
}
