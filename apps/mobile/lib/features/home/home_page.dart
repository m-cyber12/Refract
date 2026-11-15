import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../import/capture_jobs_page.dart';
import '../library/library_page.dart';
import '../memory/memory_page.dart';
import '../recall/recall_page.dart';
import '../xray/xray_page.dart';
import '../signal/signal_page.dart';
import '../../design_system/widgets/prism_mark.dart';
import '../../design_system/widgets/brand_wordmark.dart';

/// Home — personal command center (spec §9.1).
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const _HomeTab(),
      const MemoryPage(),
      const LibraryTabInline(),
      const RecallPage(),
      const XrayPage(),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: 'Memory'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.manage_search), selectedIcon: Icon(Icons.manage_search), label: 'Recall'),
          NavigationDestination(icon: Icon(Icons.visibility_outlined), selectedIcon: Icon(Icons.visibility), label: 'X-Ray'),
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
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(children: [
                const PrismMark(size: 30),
                const SizedBox(width: 12),
                const BrandWordmark(),
                const Spacer(),
                IconButton.filledTonal(tooltip: 'Import content', icon: const Icon(Icons.add), onPressed: () => context.push('/import')),
                const SizedBox(width: 4),
                IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune_rounded), onPressed: () => context.push('/settings')),
              ]),
            ),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('YOUR SPACE, IN FOCUS', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text('A clearer view\nof what matters.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(height: 1.08)),
              const SizedBox(height: 10),
              Text('Capture what you want to keep. Find your way back to it, on your terms.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(onPressed: () => context.push('/import'), icon: const Icon(Icons.add, size: 20), label: const Text('Import content')),
                OutlinedButton.icon(onPressed: () => context.push('/sense'), icon: const Icon(Icons.inbox_outlined, size: 19), label: const Text('Review inbox')),
              ]),
            ]),
          )),
          SliverToBoxAdapter(child: ref.watch(captureJobsProvider).when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => ListTile(title: const Text('Capture job history unavailable'), trailing: const Icon(Icons.pending_actions), onTap: () => context.push('/capture/jobs')),
            data: (jobs) { final pending = jobs.where((j) => j['status'] != 'completed' && j['status'] != 'cancelled').length;
              return pending == 0 ? const SizedBox.shrink() : ListTile(title: Text('$pending approved captures need attention'), subtitle: const Text('Review job states; nothing is retried automatically.'), trailing: const Icon(Icons.pending_actions), onTap: () => context.push('/capture/jobs')); })),
          const SliverToBoxAdapter(child: DailySignalPreview()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Expanded(child: Text('Needs your review', style: Theme.of(context).textTheme.titleLarge)),
                TextButton(onPressed: () => context.push('/sense'), child: const Text('Rules')),
              ]),
            ),
          ),
          _smartInboxSliver(context, ref),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Recently captured', style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(spacing: 8, children: [
              TextButton.icon(onPressed: () => context.push('/knowledge/map'), icon: const Icon(Icons.scatter_plot_outlined, size: 18), label: const Text('Knowledge map')),
              TextButton.icon(onPressed: () => context.push('/vault'), icon: const Icon(Icons.verified_user_outlined, size: 18), label: const Text('Evidence vault')),
            ]),
          )),
          items.when(
            data: (list) => list.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Nothing here yet. Share an article into REFRACT or import one manually.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

Widget _smartInboxSliver(BuildContext context, WidgetRef ref) {
  final decisions = ref.watch(senseDecisionsProvider);
  return decisions.when(
    data: (list) {
      final pending = list.where((d) => d.decision == 'smart_suggest' && !d.undone).toList();
      if (pending.isEmpty) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Nothing needs review.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
