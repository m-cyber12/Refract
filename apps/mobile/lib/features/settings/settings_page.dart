import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/repository.dart';

/// Settings — privacy & sovereignty controls (export / delete), spec §11.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String? _lastExport;

  Future<void> _export() async {
    final repo = await ref.read(bootstrapProvider.future);
    final json = repo.export();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/refract-export.json');
    await file.writeAsString(json);
    setState(() => _lastExport = file.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Local-first'),
            subtitle: Text('All data stays on this device. No account, no cloud, no telemetry.'),
          ),
          ListTile(leading:const Icon(Icons.forum_outlined),title:const Text('Multiplayer Margins'),subtitle:const Text('Selected annotations, research lists and optional encrypted exchange'),onTap:()=>context.push('/margins')),
          ListTile(leading:const Icon(Icons.hub_outlined),title:const Text('Knowledge Hub'),subtitle:const Text('Decisions, Knowledge Map, optional compression and source history'),onTap:()=>context.push('/knowledge')),
          ListTile(
            leading: const Icon(Icons.wb_twilight_outlined),
            title: const Text('DAILY SIGNAL & CONTEXT'),
            subtitle: const Text('Edition cadence, optional sections, date candidates and reading places'),
            onTap: () => context.push('/signal/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.travel_explore),
            title: const Text('REFRACT RECALL'),
            subtitle: const Text('Find sources and use the local Memory Assistant'),
            onTap: () => context.push('/recall'),
          ),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('SMART MEMORY'),
            subtitle: const Text('Topics, timeline, connections and Project Spaces'),
            onTap: () => context.push('/memory'),
          ),
          ListTile(
            leading: const Icon(Icons.rule_outlined),
            title: const Text('REFRACT SENSE RULES'),
            subtitle: const Text('Capture policies, presets, review inbox'),
            onTap: () => context.push('/sense'),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export library'),
            subtitle: Text(_lastExport == null ? 'JSON export of items, tags, collections' : 'Saved to $_lastExport'),
            onTap: _export,
          ),
        ],
      ),
    );
  }
}
