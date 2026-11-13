import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../signal/signal_page.dart';

String _date(int ts) => DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toIso8601String().substring(0, 10);
String _label(String value) => value.replaceAll('_', ' ');

void _refresh(WidgetRef ref) {
  ref.invalidate(dailySignalProvider);
  ref.invalidate(signalContextProvider);
  ref.invalidate(topicsProvider);
  ref.invalidate(entitiesProvider);
  ref.invalidate(relationshipsProvider);
  ref.invalidate(memoryTimelineProvider);
  ref.invalidate(projectsProvider);
  ref.invalidate(topicItemsProvider);
  ref.invalidate(topicEvolutionProvider);
  ref.invalidate(projectItemsProvider);
  ref.invalidate(projectTimelineProvider);
}

Future<void> _change(BuildContext context, WidgetRef ref, void Function(RefractRepository) action) async {
  try {
    final repo = await ref.read(bootstrapProvider.future);
    action(repo);
    _refresh(ref);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<String?> _text(BuildContext context, String title, {String initial = ''}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPrompt(title: title, initial: initial),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: _controller, autofocus: true, maxLines: 3),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        if (_controller.text.trim().isNotEmpty) Navigator.pop(context, _controller.text.trim());
      }, child: const Text('Save')),
    ],
  );
}

Future<T?> _pick<T>(BuildContext context, String title, List<T> values, String Function(T) label) => showDialog<T>(
  context: context,
  builder: (dialog) => SimpleDialog(
    title: Text(title),
    children: values.isEmpty
        ? [const Padding(padding: EdgeInsets.all(24), child: Text('No items available.'))]
        : values.map((value) => SimpleDialogOption(onPressed: () => Navigator.pop(dialog, value), child: Text(label(value)))).toList(),
  ),
);

Widget _data<T>(AsyncValue<List<T>> state, Widget Function(T) tile, String empty) => state.when(
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load memory: $e'))),
  data: (values) => values.isEmpty
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center)))
      : ListView(children: values.map(tile).toList()),
);

Widget _timelineTile(BuildContext context, TimelineEntry entry) => ListTile(
  leading: const Icon(Icons.schedule),
  title: Text(entry.title),
  subtitle: Text('${_date(entry.ts)} UTC · ${_label(entry.timeKind)}${entry.note == null ? '' : '\n${entry.note}'}'),
  isThreeLine: entry.note != null,
  onTap: () => context.push('/reader/${Uri.encodeComponent(entry.itemId)}'),
);

class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  bool _organizing = false;

  Future<void> _organize() async {
    setState(() => _organizing = true);
    await _change(context, ref, (repo) {
      final reports = repo.organizeLibrary();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Organized ${reports.length} item(s) locally.')));
    });
    if (mounted) setState(() => _organizing = false);
  }

  Future<void> _createProject() async {
    final name = await _text(context, 'New Project Space');
    if (name == null || !mounted) return;
    await _change(context, ref, (repo) => repo.createProject(name, ''));
  }

  Future<void> _topicAction(Topic topic, String action) async {
    if (action == 'pin') {
      await _change(context, ref, (repo) => repo.pinTopic(topic.id, !topic.pinned));
    } else if (action == 'rename') {
      final name = await _text(context, 'Rename topic', initial: topic.name);
      if (name != null && mounted) await _change(context, ref, (repo) => repo.renameTopic(topic.id, name));
    } else if (action == 'merge') {
      final choices = ref.read(topicsProvider).asData?.value.where((t) => t.id != topic.id).toList() ?? <Topic>[];
      final target = await _pick(context, 'Merge into topic', choices, (Topic t) => t.name);
      if (target != null && mounted) await _change(context, ref, (repo) => repo.mergeTopics(topic.id, target.id));
    } else if (action == 'reject') {
      await _change(context, ref, (repo) => repo.rejectTopic(topic.id));
    }
  }

  Future<void> _addLink() async {
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final items = repo.listItems(limit: 500);
      if (!mounted) return;
      final source = await _pick(context, 'Link from (recent 500 items)', items, (Item i) => i.title ?? i.id);
      if (source == null || !mounted) return;
      final target = await _pick(context, 'Link to', items.where((i) => i.id != source.id).toList(), (Item i) => i.title ?? i.id);
      if (target == null || !mounted) return;
      final kind = await _pick(context, 'Relationship type (your assertion)', ['user_added', 'related_topic', 'supporting_reference', 'contradicting_source', 'earlier_version', 'follow_up'], _label);
      if (kind == null || !mounted) return;
      final basis = await _text(context, 'Why are these connected?');
      if (basis != null && mounted) await _change(context, ref, (r) => r.addRelationship(source.id, target.id, kind, basis));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addDate() async {
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final items = repo.listItems(limit: 500);
      if (!mounted) return;
      final item = await _pick(context, 'Date for item (recent 500)', items, (Item i) => i.title ?? i.id);
      if (item == null || !mounted) return;
      final kind = await _pick(context, 'Timestamp kind', ['publication', 'modification', 'event', 'deadline'], _label);
      if (kind == null || !mounted) return;
      final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(1970), lastDate: DateTime(2200));
      if (date == null || !mounted) return;
      final ts = DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/ 1000;
      await _change(context, ref, (r) => r.setItemTime(item.id, kind, ts, 'date specified by user'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('SMART MEMORY'),
        actions: [
          IconButton(tooltip:'Knowledge Hub',icon:const Icon(Icons.hub_outlined),onPressed:()=>context.push('/knowledge')),
          IconButton(tooltip: 'Refresh', onPressed: () => _refresh(ref), icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            enabled: !_organizing,
            onSelected: (value) {
              if (value == 'organize') _organize();
              if (value == 'project') _createProject();
              if (value == 'margins') context.push('/margins');
              if (value == 'link') _addLink();
              if (value == 'date') _addDate();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'organize', child: Text('Organize existing library')),
              PopupMenuItem(value: 'project', child: Text('New Project Space')),
              PopupMenuItem(value:'margins',child:Text('Multiplayer Margins')),
              PopupMenuItem(value: 'link', child: Text('Add relationship')),
              PopupMenuItem(value: 'date', child: Text('Add explicit date')),
            ],
          ),
        ],
        bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'Timeline'), Tab(text: 'Topics'), Tab(text: 'Entities'), Tab(text: 'Connections'), Tab(text: 'Projects')]),
      ),
      body: Column(children: [
        if (_organizing) const LinearProgressIndicator(),
        const Padding(padding: EdgeInsets.all(12), child: Text('Local, rule-based suggestions — not verified facts. Originals stay unchanged. Dates extracted from text are event candidates, not confirmed events.')),
        Expanded(child: TabBarView(children: [
          _data(ref.watch(memoryTimelineProvider), (TimelineEntry e) => _timelineTile(context, e), 'No timeline yet. Capture content or organize your existing library.'),
          _data(ref.watch(topicsProvider), (Topic t) => ListTile(
            leading: Icon(t.pinned ? Icons.push_pin : Icons.topic_outlined),
            title: Text(t.name),
            subtitle: Text('${t.itemCount} item(s) · ${t.origin == 'user' ? 'user customized' : 'suggested category'}'),
            onTap: () => context.push('/memory/topic/${t.id}'),
            trailing: PopupMenuButton<String>(key: ValueKey('topic-actions-${t.id}'), onSelected: (a) => _topicAction(t, a), itemBuilder: (_) => [
              PopupMenuItem(value: 'pin', child: Text(t.pinned ? 'Unpin' : 'Pin')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'merge', child: Text('Merge into…')),
              if (t.origin == 'automatic') const PopupMenuItem(value: 'reject', child: Text('Reject category')),
            ]),
          ), 'No topics yet. Use “Organize existing library” for earlier captures.'),
          _data(ref.watch(entitiesProvider), (EntityRecord e) => ListTile(
            leading: const Icon(Icons.label_outline), title: Text(e.name),
            subtitle: Text('${e.kind} candidate · ${e.itemCount} item(s)'),
          ), 'No entities extracted yet. Extraction currently recognizes emails, ISO dates and capitalized name candidates.'),
          _data(ref.watch(relationshipsProvider), (Relationship r) => Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              title: Text('${_label(r.kind)} · ${r.confidence == 1 ? 'user-specified' : 'suggestion'}'),
              subtitle: Text('${r.basis}\nHeuristic score: ${(r.confidence * 100).round()}% — not a probability of truth'),
              trailing: IconButton(tooltip: 'Dismiss connection', icon: const Icon(Icons.close), onPressed: () => _change(context, ref, (repo) => repo.dismissRelationship(r.id))),
            ),
            _linkedItem(r.sourceItemId), _linkedItem(r.targetItemId),
          ])), 'No connections yet. Capture related content or add a relationship from the menu.'),
          _data(ref.watch(projectsProvider), (Project p) => ListTile(
            leading: const Icon(Icons.workspaces_outline), title: Text(p.name),
            subtitle: Text('${p.itemCount} item(s)${p.description?.isNotEmpty == true ? ' · ${p.description}' : ''}'),
            onTap: () => context.push('/memory/project/${p.id}'),
            trailing: IconButton(tooltip: 'Delete space (keep original items)', icon: const Icon(Icons.delete_outline), onPressed: () async {
              final confirmed = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                title: Text('Delete ${p.name}?'), content: const Text('Only the space is removed. Your original items remain in the library.'),
                actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete'))],
              ));
              if (confirmed == true && context.mounted) await _change(context, ref, (repo) => repo.deleteProject(p.id));
            }),
          ), 'Create a Project Space from the menu to group references and follow its timeline.'),
        ])),
      ]),
    ),
  );

  Widget _linkedItem(String id) {
    final item = ref.watch(itemProvider(id)).asData?.value;
    return ListTile(dense: true, leading: const Icon(Icons.article_outlined), title: Text(item?.title ?? id), onTap: () => context.push('/reader/$id'));
  }
}

class MemoryTopicPage extends ConsumerWidget {
  const MemoryTopicPage({required this.topicId, super.key});
  final String topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('KNOWLEDGE EVOLUTION')),
    body: Column(children: [
      ref.watch(topicEvolutionProvider(topicId)).when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e')),
        data: (evolution) => ExpansionTile(
          initiallyExpanded: true,
          title: Text(evolution.topic.name),
          subtitle: Text('${evolution.summary}\nCapture history only; no inference about beliefs or identity.'),
          children: evolution.stages.map((s) => ListTile(
            title: Text('${_date(s.fromTs)} – ${_date(s.toTs)} UTC'), subtitle: Text(s.description),
          )).toList(),
        ),
      ),
      Expanded(child: _data(ref.watch(topicItemsProvider(topicId)), (Item i) => ListTile(
        title: Text(i.title ?? i.id), subtitle: Text('Captured ${_date(i.importTs)} UTC'),
        onTap: () => context.push('/reader/${i.id}'),
      ), 'No items in this topic.')),
    ]),
  );
}

class MemoryProjectPage extends ConsumerWidget {
  const MemoryProjectPage({required this.projectId, super.key});
  final String projectId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    try {
      final repo = await ref.read(bootstrapProvider.future);
      final existing = repo.projectItems(projectId).map((i) => i.id).toSet();
      final choices = repo.listItems(limit: 500).where((i) => !existing.contains(i.id)).toList();
      if (!context.mounted) return;
      final item = await _pick(context, 'Add reference (recent 500)', choices, (Item i) => i.title ?? i.id);
      if (item != null && context.mounted) await _change(context, ref, (r) => r.projectAddItem(projectId, item.id));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).asData?.value ?? <Project>[];
    final name = projects.where((p) => p.id == projectId).map((p) => p.name).firstOrNull ?? 'Project Space';
    return DefaultTabController(length: 3, child: Scaffold(
      appBar: AppBar(title: Text(name), actions: [IconButton(tooltip:'Project Knowledge Hub',icon:const Icon(Icons.hub_outlined),onPressed:()=>context.push('/knowledge?project=${Uri.encodeComponent(projectId)}')),IconButton(tooltip: 'Add reference', onPressed: () => _add(context, ref), icon: const Icon(Icons.add))], bottom: const TabBar(tabs: [Tab(text: 'References'), Tab(text: 'Timeline'), Tab(text: 'Context')])),
      body: TabBarView(children: [
        _data(ref.watch(projectItemsProvider(projectId)), (Item i) => ListTile(
          title: Text(i.title ?? i.id), onTap: () => context.push('/reader/${i.id}'),
          trailing: IconButton(tooltip: 'Remove from project (keep item)', icon: const Icon(Icons.remove_circle_outline), onPressed: () => _change(context, ref, (r) => r.projectRemoveItem(projectId, i.id))),
        ), 'Add a reference with +. Original items stay in your library.'),
        _data(ref.watch(projectTimelineProvider(projectId)), (TimelineEntry e) => _timelineTile(context, e), 'No project events yet.'),
        SingleChildScrollView(child: SignalContextPanel(projectId: projectId)),
      ]),
    ));
  }
}
