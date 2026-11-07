import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/repository.dart';

/// REFRACT SENSE RULES — capture policies, presets, and the review inbox
/// (Phase II master spec §3.3, §4). All decisions are transparent and
/// reversible; nothing here silently overrides an explicit user rule.
class SensePage extends ConsumerStatefulWidget {
  const SensePage({super.key});

  @override
  ConsumerState<SensePage> createState() => _SensePageState();
}

class _SensePageState extends ConsumerState<SensePage> {
  static const presets = ['conservative', 'balanced', 'research', 'personal_archive'];
  static const kinds = ['allow_source', 'deny_source', 'allow_category', 'confirm_category'];

  String _preset = '';
  List<SenseRule> _rules = [];
  List<CaptureDecisionRecord> _decisions = [];
  bool _loading = true;

  final _nameCtl = TextEditingController();
  final _patternCtl = TextEditingController();
  String _newKind = 'allow_category';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final repo = await ref.read(bootstrapProvider.future);
    setState(() {
      _preset = repo.senseSettingGet('active_preset').ifEmpty('balanced');
      _rules = repo.senseRules();
      _decisions = repo.senseDecisions(limit: 50);
      _loading = false;
    });
  }

  Future<void> _applyPreset(String p) async {
    final repo = await ref.read(bootstrapProvider.future);
    repo.sensePresetSet(p);
    await _refresh();
  }

  Future<void> _toggleRule(SenseRule r, bool enabled) async {
    final repo = await ref.read(bootstrapProvider.future);
    repo.senseRuleUpsert({
      'id': r.id,
      'name': r.name,
      'kind': r.kind,
      'pattern': r.pattern,
      'enabled': enabled,
    });
    await _refresh();
  }

  Future<void> _deleteRule(SenseRule r) async {
    final repo = await ref.read(bootstrapProvider.future);
    repo.senseRuleDelete(r.id);
    await _refresh();
  }

  Future<void> _addRule() async {
    if (_nameCtl.text.trim().isEmpty || _patternCtl.text.trim().isEmpty) return;
    final repo = await ref.read(bootstrapProvider.future);
    repo.senseRuleUpsert({
      'name': _nameCtl.text.trim(),
      'kind': _newKind,
      'pattern': _patternCtl.text.trim(),
      'enabled': true,
    });
    _nameCtl.clear();
    _patternCtl.clear();
    await _refresh();
  }

  Future<void> _review(CaptureDecisionRecord d, String action) async {
    final repo = await ref.read(bootstrapProvider.future);
    repo.senseReview(d.id, action);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('REFRACT SENSE RULES')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Capture preset', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: presets.contains(_preset) ? _preset : 'balanced',
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: presets
                .map((p) => DropdownMenuItem(value: p, child: Text(p.replaceAll('_', ' '))))
                .toList(),
            onChanged: (p) => p != null ? _applyPreset(p) : null,
          ),
          const SizedBox(height: 4),
          const Text(
            'Presets install rules; your custom rules are never overwritten.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Divider(height: 24),
          const Text('Rules', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._rules.map((r) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${r.name}  ·  ${r.kind} "${r.pattern}"'),
                subtitle: Text(r.preset == 'custom' ? 'custom rule' : 'from preset ${r.preset}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(value: r.enabled, onChanged: (v) => _toggleRule(r, v)),
                  if (r.preset == 'custom')
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRule(r)),
                ]),
              )),
          const Divider(height: 24),
          const Text('Add rule', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: _nameCtl, decoration: const InputDecoration(labelText: 'Name', isDense: true)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _newKind,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: kinds.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: (k) => setState(() => _newKind = k ?? _newKind),
          ),
          const SizedBox(height: 6),
          TextField(controller: _patternCtl, decoration: const InputDecoration(labelText: 'Pattern (domain, category, or *)', isDense: true)),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _addRule, child: const Text('Add rule')),
          ),
          const Divider(height: 24),
          const Text('Review inbox & capture history', style: TextStyle(fontWeight: FontWeight.bold)),
          if (_decisions.isEmpty) const Text('No captures yet.', style: TextStyle(color: Colors.grey)),
          ..._decisions.map((d) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${d.decision.replaceAll('_', ' ')} · ${d.category} · score ${d.score.toStringAsFixed(2)}${d.undone ? ' · undone' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(d.explanation, style: const TextStyle(fontSize: 12)),
                    if (!d.undone)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (d.decision == 'smart_suggest') ...[
                          TextButton(onPressed: () => _review(d, 'approve'), child: const Text('Save')),
                          TextButton(onPressed: () => _review(d, 'dismiss'), child: const Text('Ignore')),
                        ],
                        TextButton(onPressed: () => _review(d, 'undo'), child: const Text('Undo')),
                      ]),
                  ]),
                ),
              )),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
