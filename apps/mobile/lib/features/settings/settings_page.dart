import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/repository.dart';
import '../../design_system/appearance.dart';
import '../../design_system/widgets/prism_mark.dart';
import '../../design_system/widgets/brand_wordmark.dart';

/// Settings — privacy & sovereignty controls (export / delete), spec §11.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.writeExport});
  /// Test seam for the local plaintext JSON destination.
  final Future<String> Function(String json)? writeExport;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String? _lastExport;
  bool _confirmingExport = false;
  bool _exportBusy = false;

  Future<void> _export() async {
    if (_confirmingExport || _exportBusy) return;
    _confirmingExport = true;
    bool? approved;
    try {
      approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Write a plaintext JSON copy?'),
        content: const Text('This is not an encrypted backup and cannot restore the complete library. It includes extracted text and metadata for up to 10,000 items, plus tag and collection lists; originals and other library data are omitted. It writes an unencrypted file in app documents and replaces the previous JSON copy. OS backups may retain copies. Continue only if you accept these limits.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write plaintext JSON')),
        ],
      ));
    } finally { _confirmingExport = false; }
    if (approved != true || !mounted) return;
    setState(() { _exportBusy = true; _lastExport = null; });
    try {
      final repo = await ref.read(bootstrapProvider.future);
      if (!mounted) return;
      final json = repo.export();
      final String path;
      if (widget.writeExport != null) {
        path = await widget.writeExport!(json);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/refract-export.json');
        await file.writeAsString(json);
        path = file.path;
      }
      if (mounted) setState(() => _lastExport = 'Plaintext JSON written to $path. This is not a full backup.');
    } catch (_) {
      if (mounted) setState(() => _lastExport = 'JSON export failed or could not be confirmed. Check the app documents location before retrying.');
    } finally { if (mounted) setState(() => _exportBusy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = ref.watch(appearanceProvider);
    return Scaffold(
      appBar: AppBar(title: Row(children: [const PrismMark(size: 25), const SizedBox(width: 10),
        const BrandWordmark(width: 105)])),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Your space. Your preferences.', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 26),
          const _SettingsHeading('YOUR EXPERIENCE'),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.contrast_rounded), const SizedBox(width: 12), Text('Appearance', style: theme.textTheme.titleMedium)]),
            const SizedBox(height: 6),
            Text('Choose how REFRACT looks on this device.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final mode in ThemeMode.values) ChoiceChip(
                label: Text(switch (mode) { ThemeMode.system => 'System', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark' }),
                selected: selected == mode,
                onSelected: (_) async {
                  final saved = await ref.read(appearanceProvider.notifier).setMode(mode);
                  if (!saved && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appearance changed for this session, but could not be saved.')));
                },
              ),
            ]),
          ]))),
          _settingsTile(Icons.pending_actions, 'Capture jobs', 'Resume or cancel approved saves after interruption', () => context.push('/capture/jobs')),
          _settingsTile(Icons.rule_outlined, 'Capture rules & inbox', 'Review local capture policies and suggestions', () => context.push('/sense')),
          _settingsTile(Icons.wb_twilight_outlined, 'Daily Signal & Context', 'Edition cadence, date candidates and reading places', () => context.push('/signal/settings')),
          const _SettingsHeading('YOUR KNOWLEDGE'),
          _settingsTile(Icons.hub_outlined, 'Smart Memory', 'Topics, timeline, connections and Project Spaces', () => context.push('/memory')),
          _settingsTile(Icons.account_tree_outlined, 'Knowledge Hub', 'Decisions, maps and source history', () => context.push('/knowledge')),
          _settingsTile(Icons.travel_explore, 'Recall', 'Find sources and use the local Memory Assistant', () => context.push('/recall')),
          const _SettingsHeading('DATA & PRIVACY'),
          Card(child: ListTile(leading: const Icon(Icons.cloud_off_outlined), title: const Text('Local-first'),
            subtitle: const Text('Local storage by default. No mandatory account, cloud or telemetry. External exports and collaboration require explicit action.'))),
          _settingsTile(Icons.verified_user_outlined, 'Evidence vault', 'Inspect locally recorded evidence and its limits', () => context.push('/vault')),
          _settingsTile(Icons.download_outlined, 'Write partial plaintext JSON', _lastExport ?? 'Not an encrypted backup; originals and other library data omitted', _exportBusy ? null : _export),
          const _SettingsHeading('CONNECTED SERVICES'),
          _settingsTile(Icons.extension_outlined, 'Optional integrations', 'Consent-gated copies, reviewed calendar files and integration research', () => context.push('/integrations')),
          _settingsTile(Icons.forum_outlined, 'Multiplayer Margins', 'Selected annotations and optional encrypted exchange', () => context.push('/margins')),
          const _SettingsHeading('ABOUT'),
          _settingsTile(Icons.info_outline, 'Open-source licenses', 'View the licenses for components used in REFRACT', () => showLicensePage(context: context, applicationName: 'REFRACT', applicationVersion: '0.1.0')),
          const SizedBox(height: 18),
          Text('REFRACT  ·  Your knowledge, on your terms', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _settingsTile(IconData icon, String title, String subtitle, VoidCallback? onTap) =>
    ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      leading: Icon(icon), title: Text(title), subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right), onTap: onTap);
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading(this.label);
  final String label;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
  );
}
