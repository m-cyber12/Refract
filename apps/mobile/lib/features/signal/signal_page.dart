import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/repository.dart';

const signalSections = <String,String>{'recent':'Recently captured','topics':'Emerging topics','discoveries':'Connected discoveries','upcoming':'Upcoming dates','unfinished':'Unfinished knowledge','changes':'Marked changes','reading':'Continue reading','gaps':'Knowledge gaps','suggestions':'Suggested reading'};
String _utc(int ts) => DateTime.fromMillisecondsSinceEpoch(ts * 1000,isUtc:true).toIso8601String().substring(0,10);

Future<void> signalChange(BuildContext context, WidgetRef ref, void Function(RefractRepository) action, {String? message}) async {
  try {
    final repo = await ref.read(bootstrapProvider.future);
    action(repo);
    ref.invalidate(dailySignalProvider);
    ref.invalidate(signalConfigProvider);
    ref.invalidate(signalContextProvider);
    if (message != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  } catch(e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not update Signal: $e')));
  }
}

class DailySignalPreview extends ConsumerWidget {
  const DailySignalPreview({super.key});
  @override
  Widget build(BuildContext context,WidgetRef ref) => Card(margin:const EdgeInsets.symmetric(horizontal:20,vertical:8),child:ref.watch(dailySignalProvider).when(
    loading:()=>const Padding(padding:EdgeInsets.all(16),child:LinearProgressIndicator()),
    error:(e,_)=>ListTile(title:const Text('Daily Signal unavailable'),subtitle:Text('$e'),onTap:()=>context.push('/signal')),
    data:(edition)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      ListTile(leading:const Icon(Icons.wb_twilight_outlined),title:const Text('DAILY SIGNAL'),subtitle:Text(edition.message),onTap:()=>context.push('/signal'),trailing:const Icon(Icons.chevron_right)),
      if (edition.enabled && !edition.quiet) Padding(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Text('${edition.entries.length} observations · ${edition.events.length} date candidates / user-confirmed dates. Open for sources and controls.')),
    ]),
  ));
}

class DailySignalPage extends ConsumerWidget {
  const DailySignalPage({super.key});
  @override
  Widget build(BuildContext context,WidgetRef ref) => Scaffold(
    appBar:AppBar(title:const Text('DAILY SIGNAL'),actions:[
      IconButton(tooltip:'Generate / refresh edition now',icon:const Icon(Icons.refresh),onPressed:()=>signalChange(context,ref,(repo)=>repo.dailySignal(refresh:true))),
      IconButton(tooltip:'Signal & Context settings',icon:const Icon(Icons.tune),onPressed:()=>context.push('/signal/settings')),
    ]),
    body:ref.watch(dailySignalProvider).when(
      loading:()=>const Center(child:CircularProgressIndicator()),
      error:(e,_)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Could not load Daily Signal: $e'))),
      data:(edition)=>ListView(padding:const EdgeInsets.all(16),children:[
        Text(edition.message,style:Theme.of(context).textTheme.titleMedium),
        if (edition.enabled) Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('Edition ${_utc(edition.generatedTs)} UTC · ${edition.nextRefreshTs==null ? 'manual refresh' : 'next automatic refresh on opening after ${_utc(edition.nextRefreshTs!)} UTC'}. No notifications.')),
        for (final section in signalSections.entries) ...[
          if (edition.entries.any((e)=>e.section==section.key) || (section.key=='upcoming' && edition.events.isNotEmpty)) Padding(padding:const EdgeInsets.only(top:16,bottom:8),child:Text(section.value,style:Theme.of(context).textTheme.titleMedium)),
          ...edition.entries.where((e)=>e.section==section.key).map((e)=>SignalEntryCard(entry:e,dismissible:true)),
          if(section.key=='upcoming') ...edition.events.map((e)=>SignalEventCard(event:e)),
        ],
        ExpansionTile(title:const Text('Scope, privacy & limitations'),children:edition.limitations.map((s)=>Padding(padding:const EdgeInsets.all(8),child:Text(s))).toList()),
      ]),
    ),
  );
}

class SignalEntryCard extends ConsumerWidget {
  const SignalEntryCard({required this.entry,this.dismissible=false,super.key});
  final SignalEntry entry;
  final bool dismissible;
  @override
  Widget build(BuildContext context,WidgetRef ref) => Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Expanded(child:Text(entry.title,style:Theme.of(context).textTheme.titleSmall)),if(dismissible)IconButton(tooltip:'Dismiss observation',onPressed:()=>signalChange(context,ref,(r)=>r.dismissSignal(entry.key)),icon:const Icon(Icons.close))]),
    Text(entry.explanation),
    Padding(padding:const EdgeInsets.only(top:6),child:Text('${entry.status.replaceAll('_',' ')}${entry.ts==null ? '' : ' · ${_utc(entry.ts!)} UTC'}',style:Theme.of(context).textTheme.bodySmall)),
    Wrap(spacing:8,children:[
      for(final id in entry.itemIds.take(5)) TextButton.icon(onPressed:()=>context.push('/reader/${Uri.encodeComponent(id)}${entry.blockIdx==null ? '' : '?block=${entry.blockIdx}'}'),icon:const Icon(Icons.article_outlined,size:16),label:Text(entry.section=='reading' ? 'Resume saved place' : 'Source ${entry.itemIds.indexOf(id)+1}')),
      if(entry.projectId!=null)TextButton(onPressed:()=>context.push('/memory/project/${entry.projectId}'),child:const Text('Project Space')),
    ]),
    if(entry.itemIds.length>5)Text('${entry.itemIds.length-5} additional sources are associated with this observation; open the Project Space when available.'),
  ])));
}

class SignalEventCard extends ConsumerWidget {
  const SignalEventCard({required this.event,super.key});
  final SignalEvent event;
  @override
  Widget build(BuildContext context,WidgetRef ref) => Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(event.title,style:Theme.of(context).textTheme.titleSmall),
    Text('${_utc(event.eventTs)} UTC · ${event.category.replaceAll('_',' ')}'),
    Text(event.status=='confirmed' ? 'USER-CONFIRMED — not externally verified' : 'UNCONFIRMED DATE CANDIDATE — not a guaranteed event'),
    Text('Extraction heuristic: ${event.confidence.toStringAsFixed(2)} · not a truth probability',style:Theme.of(context).textTheme.bodySmall),
    const SizedBox(height:8),SelectableText(event.evidence),
    TextButton.icon(onPressed:()=>context.push('/reader/${Uri.encodeComponent(event.itemId)}?block=${event.blockIdx}'),icon:const Icon(Icons.article_outlined),label:const Text('Open date evidence')),
    Wrap(spacing:8,children:[
      if(event.status!='confirmed')TextButton(onPressed:()=>signalChange(context,ref,(r)=>r.reviewSignalEvent(event.id,'confirmed')),child:const Text('Confirm date')),
      if(event.status=='confirmed')TextButton(onPressed:()=>signalChange(context,ref,(r)=>r.reviewSignalEvent(event.id,'unconfirmed')),child:const Text('Undo confirmation')),
      TextButton(onPressed:()=>signalChange(context,ref,(r)=>r.reviewSignalEvent(event.id,'dismissed')),child:const Text('Dismiss candidate')),
    ]),
  ])));
}

/// Context is fetched only when expanded, never via a reading-interrupting popup.
class SignalContextPanel extends ConsumerStatefulWidget {
  const SignalContextPanel({this.itemId,this.projectId,super.key});
  final String? itemId;
  final String? projectId;
  @override
  ConsumerState<SignalContextPanel> createState()=>_SignalContextPanelState();
}
class _SignalContextPanelState extends ConsumerState<SignalContextPanel> {
  bool _open=false;
  @override
  Widget build(BuildContext context) {
    final config=ref.watch(signalConfigProvider);
    if(config.asData?.value.contextEnabled==false)return const SizedBox.shrink();
    final request=jsonEncode({'item_id':widget.itemId,'project_id':widget.projectId});
    final data=_open ? ref.watch(signalContextProvider(request)) : null;
    return ExpansionTile(title:const Text('REFRACT CONTEXT · optional'),subtitle:const Text('Stored connections, notes, projects and date evidence'),onExpansionChanged:(value)=>setState(()=>_open=value),children:[
      if(data!=null)data.when(
        loading:()=>const LinearProgressIndicator(),
        error:(e,_)=>Padding(padding:const EdgeInsets.all(12),child:Text('Context unavailable: $e')),
        data:(value)=>Column(children:[
          Padding(padding:const EdgeInsets.all(12),child:Text(value.message)),
          if(value.entries.isEmpty&&value.events.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('No stored context found. No extra information needs to be collected.')),
          ...value.entries.map((e)=>SignalEntryCard(entry:e)),...value.events.map((e)=>SignalEventCard(event:e)),
        ]),
      ),
    ]);
  }
}

class SignalSettingsPage extends ConsumerStatefulWidget {
  const SignalSettingsPage({super.key});
  @override
  ConsumerState<SignalSettingsPage> createState()=>_SignalSettingsPageState();
}
class _SignalSettingsPageState extends ConsumerState<SignalSettingsPage> {
  bool _saving=false;
  Future<void> _save(SignalConfig config,String key,dynamic value)async {
    setState(()=>_saving=true);
    await signalChange(context,ref,(r)=>r.configureSignal(config.changed(key,value)));
    if(mounted)setState(()=>_saving=false);
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Signal & Context controls')),
    body:ref.watch(signalConfigProvider).when(
      loading:()=>const Center(child:CircularProgressIndicator()),error:(e,_)=>Center(child:Text('Settings unavailable: $e')),
      data:(c)=>ListView(children:[
        if(_saving)const LinearProgressIndicator(),
        const Padding(padding:EdgeInsets.all(16),child:Text('Local, on-demand editions. No push notifications, calendar integration or automatic reading surveillance. Reading places are saved only when you explicitly choose to.')),
        SwitchListTile(title:const Text('Enable Daily Signal'),value:c.enabled,onChanged:_saving?null:(v)=>_save(c,'enabled',v)),
        SwitchListTile(title:const Text('Optional contextual panels'),value:c.contextEnabled,onChanged:_saving?null:(v)=>_save(c,'context_enabled',v)),
        ListTile(title:const Text('Edition frequency'),trailing:DropdownButton<String>(value:c.frequency,onChanged:_saving?null:(v){if(v!=null)_save(c,'frequency',v);},items:const[DropdownMenuItem(value:'daily',child:Text('Daily')),DropdownMenuItem(value:'weekly',child:Text('Weekly')),DropdownMenuItem(value:'manual',child:Text('Manual only'))])),
        ListTile(title:const Text('Lookback days'),trailing:DropdownButton<int>(value:c.lookbackDays,onChanged:_saving?null:(v){if(v!=null)_save(c,'lookback_days',v);},items:({...{1,7,14,30,90},c.lookbackDays}.toList()..sort()).map((v)=>DropdownMenuItem(value:v,child:Text('$v'))).toList())),
        ListTile(title:const Text('Upcoming date horizon'),trailing:DropdownButton<int>(value:c.upcomingDays,onChanged:_saving?null:(v){if(v!=null)_save(c,'upcoming_days',v);},items:({...{7,14,30,90,365},c.upcomingDays}.toList()..sort()).map((v)=>DropdownMenuItem(value:v,child:Text('$v days'))).toList())),
        ListTile(title:const Text('Maximum per section'),trailing:DropdownButton<int>(value:c.maxPerSection,onChanged:_saving?null:(v){if(v!=null)_save(c,'max_per_section',v);},items:List.generate(5,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1}'))))),
        SwitchListTile(title:const Text('Show unconfirmed date candidates'),subtitle:const Text('Candidates remain labeled uncertain until you confirm them.'),value:c.showUnconfirmed,onChanged:_saving?null:(v)=>_save(c,'show_unconfirmed',v)),
        const Divider(),
        for(final section in signalSections.entries)SwitchListTile(title:Text(section.value),value:c.sections.contains(section.key),onChanged:_saving?null:(v){final next=[...c.sections];if(v){next.add(section.key);}else{next.remove(section.key);}_save(c,'sections',next);}),
        ListTile(title:const Text('Clear saved reading places'),subtitle:const Text('Does not delete documents or annotations'),trailing:const Icon(Icons.delete_outline),onTap:()=>signalChange(context,ref,(r)=>r.clearReadingPlaces(),message:'Saved reading places cleared.')),
        ListTile(title:const Text('Restore dismissed observations'),subtitle:const Text('Does not reset dismissed date candidates'),onTap:()=>signalChange(context,ref,(r)=>r.resetSignalDismissals(),message:'Observation dismissals reset.')),
      ]),
    ),
  );
}
