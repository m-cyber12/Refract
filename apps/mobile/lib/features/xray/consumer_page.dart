import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/consumer_models.dart';
import '../../core/repository.dart';

String _label(String s)=>s.replaceAll('_',' ');
String _time(int ts)=>DateTime.fromMillisecondsSinceEpoch(ts*1000,isUtc:true).toIso8601String();
const _warning='Local extraction candidates, not verified transactions or legal advice. User confirmation does not verify authenticity or enforceability.';

void _invalidate(WidgetRef ref){
  ref.invalidate(consumerDocumentsProvider);ref.invalidate(consumerDocumentProvider);ref.invalidate(consumerSearchProvider);ref.invalidate(consumerCompareProvider);ref.invalidate(consumerHistoryProvider);ref.invalidate(subscriptionsProvider);ref.invalidate(upcomingEventsProvider);ref.invalidate(signalContextProvider);
}
Future<void> _change(BuildContext context,WidgetRef ref,void Function(RefractRepository) action,{String? message})async{
  try{final repo=await ref.read(bootstrapProvider.future);action(repo);_invalidate(ref);if(message!=null&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
  catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Consumer X-Ray: $e')));}
}

class ConsumerDocumentsPage extends ConsumerStatefulWidget{
  const ConsumerDocumentsPage({super.key});
  @override ConsumerState<ConsumerDocumentsPage> createState()=>_ConsumerDocumentsPageState();
}
class _ConsumerDocumentsPageState extends ConsumerState<ConsumerDocumentsPage>{
  final _query=TextEditingController();final _selected=<String>{};String _status='';String? _search;bool _busy=false;
  @override void dispose(){_query.dispose();super.dispose();}
  void _find(){FocusScope.of(context).unfocus();setState(()=>_search=jsonEncode({'query':_query.text.trim(),if(_status.isNotEmpty)'status':_status}));ref.invalidate(consumerSearchProvider(_search!));}
  Future<void> _scan()async{
    setState(()=>_busy=true);
    await _change(context,ref,(repo){final n=repo.consumerAnalyzeLibrary();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Analyzed $n non-ignored sources (most recent 500 maximum). Originals unchanged.')));});
    if(mounted)setState(()=>_busy=false);
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('CONSUMER DOCUMENTS'),actions:[IconButton(tooltip:'Analyze recent library sources (up to 500)',onPressed:_busy?null:_scan,icon:const Icon(Icons.document_scanner_outlined))]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text(_warning),const SizedBox(height:12),
      TextField(key:const ValueKey('consumer-search'),controller:_query,decoration:const InputDecoration(labelText:'Search values, fields or supporting text',hintText:'merchant, renewal, warranty, amount…',border:OutlineInputBorder()),onSubmitted:(_)=>_find()),
      Wrap(spacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[DropdownButton<String>(value:_status,onChanged:(v){if(v!=null){setState(()=>_status=v);_find();}},items:const[DropdownMenuItem(value:'',child:Text('All review states')),DropdownMenuItem(value:'unconfirmed',child:Text('Unconfirmed')),DropdownMenuItem(value:'user_confirmed',child:Text('User-confirmed')),DropdownMenuItem(value:'rejected',child:Text('Rejected'))]),FilledButton(onPressed:_find,child:const Text('Search claims')),if(_search!=null)TextButton(onPressed:()=>setState(()=>_search=null),child:const Text('Show documents'))]),
      if(_busy)const LinearProgressIndicator(),
      if(_search!=null)ref.watch(consumerSearchProvider(_search!)).when(loading:()=>const LinearProgressIndicator(),error:(e,_)=>Text('Claim search failed: $e'),data:(claims)=>Column(children:[if(claims.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No matching extracted claim found. Missing information is not proof of absence.')),...claims.map((c)=>ConsumerClaimCard(key:ValueKey(c.id),claim:c))]))
      else ...[
        if(_selected.isNotEmpty)Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[Text('${_selected.length}/5 sources selected'),TextButton(onPressed:_selected.length<2?null:()=>context.push('/xray/compare?ids=${Uri.encodeQueryComponent(jsonEncode(_selected.toList()..sort()))}'),child:const Text('Compare selected')),TextButton(onPressed:()=>setState(_selected.clear),child:const Text('Clear'))]),
        ref.watch(consumerDocumentsProvider).when(loading:()=>const LinearProgressIndicator(),error:(e,_)=>Text('Consumer documents unavailable: $e'),data:(docs)=>Column(children:[
          if(docs.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No consumer candidates yet. Import a receipt or agreement, analyze older library sources with the scanner button, or open any Reader source in Consumer X-Ray.')),
          ...docs.map((d)=>Card(child:Column(children:[
            CheckboxListTile(value:_selected.contains(d.itemId),onChanged:(v)=>setState((){if(v==true&&_selected.length<5)_selected.add(d.itemId);if(v==false)_selected.remove(d.itemId);}),title:Text(d.title),subtitle:Text('${d.categories.join(', ')}\n${d.claimCount} candidates · ${d.unconfirmedCount} unconfirmed${d.truncated?' · PARTIAL SCAN':''}')),
            TextButton.icon(onPressed:()=>context.push('/xray/document/${Uri.encodeComponent(d.itemId)}'),icon:const Icon(Icons.receipt_long_outlined),label:const Text('Inspect evidence')),
          ]))),
        ])),
      ],
    ]),
  );
}

class ConsumerDocumentPage extends ConsumerStatefulWidget{
  const ConsumerDocumentPage({required this.itemId,super.key});final String itemId;
  @override ConsumerState<ConsumerDocumentPage> createState()=>_ConsumerDocumentPageState();
}
class _ConsumerDocumentPageState extends ConsumerState<ConsumerDocumentPage>{
  bool _busy=false;ConsumerOriginalCheck? _integrity;
  Future<void> _check()async{
    setState(()=>_busy=true);try{final repo=await ref.read(bootstrapProvider.future);final value=repo.consumerCheckOriginal(widget.itemId);if(mounted)setState(()=>_integrity=value);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Original check unavailable: $e')));}finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _track()async{
    final yes=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('Track confirmed field snapshot?'),content:const Text('Only current, user-confirmed service and subscription fields are copied. The result is marked imported, not active or independently verified. Later claim reviews do not silently update this snapshot. Repeating this action returns the existing record.'),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('Create imported record'))]));
    if(yes==true&&mounted)await _change(context,ref,(r)=>r.consumerTrackSubscription(widget.itemId),message:'Imported subscription snapshot available in X-Ray. Not proof of active billing.');
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('CONSUMER EVIDENCE'),actions:[IconButton(tooltip:'Re-analyze without resetting reviews',icon:const Icon(Icons.refresh),onPressed:()=>_change(context,ref,(r)=>r.consumerAnalyze(widget.itemId)))]),
    body:ref.watch(consumerDocumentProvider(widget.itemId)).when(loading:()=>const Center(child:CircularProgressIndicator()),error:(e,_)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Source analysis unavailable: $e'))),data:(doc)=>ListView(padding:const EdgeInsets.all(16),children:[
      Text(doc.title,style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:8),const Text(_warning),
      Text('Captured ${_time(doc.capturedTs)}'),if(doc.sourceUrl!=null)SelectableText(doc.sourceUrl!),
      TextButton.icon(onPressed:()=>context.push('/reader/${Uri.encodeComponent(doc.itemId)}'),icon:const Icon(Icons.article_outlined),label:const Text('Open full original source in Reader')),
      if(!doc.scanned)const Text('This source has not been analyzed. Use the re-analyze button.'),
      if(doc.truncated)const Text('PARTIAL VIEW / SCAN: extraction or display limits were reached. Review the full source; unextracted information may exist.'),
      ExpansionTile(title:const Text('Original integrity (not authenticity)'),children:[
        if(doc.originalSha256!=null)Padding(padding:const EdgeInsets.all(8),child:SelectableText('Recorded SHA-256: ${doc.originalSha256}')),
        const Padding(padding:EdgeInsets.all(8),child:Text('A matching hash only establishes consistency with recorded bytes. It does not prove origin, authenticity, payment, legal validity or enforceability.')),
        TextButton(onPressed:_busy?null:_check,child:const Text('Compare original bytes to recorded hash')),
        if(_busy)const LinearProgressIndicator(),
        if(_integrity!=null)Padding(padding:const EdgeInsets.all(8),child:Text('${_label(_integrity!.status)}\n${_integrity!.explanation}')),
      ]),
      if(doc.claims.any((c)=>c.field=='service'))TextButton.icon(onPressed:_track,icon:const Icon(Icons.add_card),label:const Text('Track from confirmed subscription claims')),
      if(doc.claims.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No structured candidates were found by these rules. This does not mean the source lacks relevant information.')),
      ...doc.claims.map((c)=>ConsumerClaimCard(key:ValueKey(c.id),claim:c)),
      ExpansionTile(title:const Text('Extraction limits & evidence distinctions'),children:doc.limitations.map((s)=>Padding(padding:const EdgeInsets.all(8),child:Text(s))).toList()),
    ])),
  );
}

class ConsumerClaimCard extends ConsumerStatefulWidget{
  const ConsumerClaimCard({required this.claim,super.key});final ConsumerClaim claim;
  @override ConsumerState<ConsumerClaimCard> createState()=>_ConsumerClaimCardState();
}
class _ConsumerClaimCardState extends ConsumerState<ConsumerClaimCard>{
  bool _history=false;bool _busy=false;
  Future<void> _review(String status)async{setState(()=>_busy=true);await _change(context,ref,(r)=>r.consumerReview(widget.claim.id,status));if(mounted)setState(()=>_busy=false);}
  @override Widget build(BuildContext context){final c=widget.claim;return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('${_label(c.category)} · ${_label(c.field)}',style:Theme.of(context).textTheme.titleSmall),SelectableText(c.value),
    if(c.valueType=='money')Text('Parsed amount ×100: ${c.amountMinor} · currency ${c.currency??'UNSPECIFIED / AMBIGUOUS — check passage'}'),
    if(c.dateTs!=null)Text('Parsed UTC date: ${_time(c.dateTs!)} — candidate, not guaranteed'),
    Text(c.status=='user_confirmed'?'USER-CONFIRMED — not independent verification':c.status=='rejected'?'REJECTED — retained with audit history':'UNCONFIRMED EXTRACTION'),
    Text('Extraction heuristic ${c.confidence.toStringAsFixed(2)} — not a truth probability'),
    if(!c.sourceMatches)const Text('STALE EVIDENCE: current parsed source no longer matches this recorded block. Do not treat it as current terms.'),
    const SizedBox(height:8),const Text('Exact supporting passage:'),SelectableText(c.quote),
    TextButton.icon(onPressed:()=>context.push('/reader/${Uri.encodeComponent(c.itemId)}?block=${c.blockIdx}'),icon:const Icon(Icons.article_outlined),label:const Text('Open supporting source block')),
    Wrap(spacing:8,children:[
      if(c.status!='user_confirmed')TextButton(onPressed:_busy||!c.sourceMatches?null:()=>_review('user_confirmed'),child:const Text('Confirm extraction')),
      if(c.status!='rejected')TextButton(onPressed:_busy?null:()=>_review('rejected'),child:const Text('Reject extraction')),
      if(c.status!='unconfirmed')TextButton(onPressed:_busy?null:()=>_review('unconfirmed'),child:const Text('Reset to unconfirmed')),
    ]),
    if(_busy)const LinearProgressIndicator(),
    ExpansionTile(title:const Text('Extraction provenance & review history'),onExpansionChanged:(v)=>setState(()=>_history=v),children:[
      Padding(padding:const EdgeInsets.all(8),child:SelectableText('Source ${c.itemId}\nBlock ${c.blockIdx} · UTF-8 bytes ${c.startByte}–${c.endByte}\nExtracted ${_time(c.extractedTs)}\nRules ${c.extractorVersion}\nParsed block SHA-256 ${c.sourceTextSha256}\nMatches current parsed block: ${c.sourceMatches}. This is not an original-authenticity check.')),
      if(_history)ref.watch(consumerHistoryProvider(c.id)).when(loading:()=>const LinearProgressIndicator(),error:(e,_)=>Text('Review history unavailable: $e'),data:(rows)=>Column(children:[if(rows.isEmpty)const ListTile(title:Text('No review transitions recorded.')),...rows.map((r)=>ListTile(title:Text('${_label(r.fromStatus)} → ${_label(r.toStatus)}'),subtitle:Text(_time(r.reviewedTs))))])),
    ]),
  ])));}
}

class ConsumerComparePage extends ConsumerWidget{
  const ConsumerComparePage({required this.idsJson,super.key});final String idsJson;
  @override Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('SOURCE COMPARISON')),body:ref.watch(consumerCompareProvider(idsJson)).when(loading:()=>const Center(child:CircularProgressIndicator()),error:(e,_)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Comparison unavailable: $e'))),data:(result)=>ListView(padding:const EdgeInsets.all(16),children:[
    Text(result.explanation),
    if(result.fields.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No current, non-rejected comparable fields found. No agreement or contradiction can be established.')),
    ...result.fields.map((f)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Padding(padding:const EdgeInsets.only(top:16,bottom:8),child:Text('${_label(f.field)} · ${_label(f.result)}',style:Theme.of(context).textTheme.titleMedium)),
      if(f.missingItemIds.isNotEmpty)Text('Not found among extracted claims for: ${f.missingItemIds.join(', ')}. This does not prove absence in those originals.'),
      ...f.claims.map((c)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Source ${c.itemId}'),ConsumerClaimCard(key:ValueKey(c.id),claim:c)])),
    ])),
  ])));
}
