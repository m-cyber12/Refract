import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/repository.dart';
import 'knowledge_widgets.dart';

class CompressionsPanel extends ConsumerWidget{
 const CompressionsPanel({super.key,this.projectId});final String? projectId;
 @override Widget build(BuildContext context,WidgetRef ref)=>ListView(padding:const EdgeInsets.all(16),children:[
 const Text('Memory Compression is optional. These are deterministic, extractive snapshots, not model-written summaries. Originals remain independent and unchanged.'),
 FilledButton.icon(onPressed:()=>context.push('/knowledge/compress${projectId==null?'':'?kind=project&id=${Uri.encodeComponent(projectId!)}'}'),icon:const Icon(Icons.summarize_outlined),label:const Text('Create extractive overview')),
 const Text('Latest 100 saved overviews across all scopes'),
 ref.watch(compressionsProvider).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(values)=>Column(children:[if(values.isEmpty)const ListTile(title:Text('No optional overviews saved.')),...values.map((v)=>Card(child:ListTile(title:Text(v['title'] as String),subtitle:Text('${v['scope_kind']} · generated ${knowledgeTime(v['generated_ts'])}'),onTap:()=>context.push('/knowledge/compression/${v['id']}'))))])),
 ]);
}
class CompressionCreatePage extends ConsumerStatefulWidget{
 const CompressionCreatePage({super.key,this.scopeKind='selected',this.scopeId,this.sourceId});final String scopeKind;final String? scopeId,sourceId;
 @override ConsumerState<CompressionCreatePage> createState()=>_CompressionCreatePageState();
}
class _CompressionCreatePageState extends ConsumerState<CompressionCreatePage>{
 final _title=TextEditingController();late String _scope;String? _scopeId;late List<String> _sources;bool _saving=false;
 @override void initState(){super.initState();_scope=widget.scopeKind;_scopeId=widget.scopeId;_sources=[if(widget.sourceId!=null)widget.sourceId!];}
 @override void dispose(){_title.dispose();super.dispose();}
 Future<void> _create()async{setState(()=>_saving=true);String? id;final ok=await knowledgeChange(context,ref,(r){id=r.createCompression({'title':_title.text,'scope_kind':_scope,'scope_id':_scopeId,'item_ids':_scope=='selected'?_sources:<String>[]})['id'] as String;});if(!mounted){return;}setState(()=>_saving=false);if(ok){context.replace('/knowledge/compression/$id');}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Create optional overview')),body:ListView(padding:const EdgeInsets.all(16),children:[
 const Text('Select up to 30 documents, or use a bounded project/topic/collection window (first 30 by ID). Quotes, dates and references stay source-linked. No source will be replaced.'),
 TextField(controller:_title,maxLength:200,decoration:const InputDecoration(labelText:'Title (optional)')),
 DropdownButtonFormField<String>(initialValue:_scope,decoration:const InputDecoration(labelText:'Scope'),items:['selected','project','topic','collection'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState((){_scope=v!;_scopeId=null;})),
 if(_scope=='selected')KnowledgeSourcePicker(selected:_sources,onChanged:(v)=>setState(()=>_sources=v)),
 if(_scope=='project')KnowledgeProjectPicker(value:_scopeId,onChanged:(v)=>setState(()=>_scopeId=v)),
 if(_scope=='topic')ref.watch(topicsProvider).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(values)=>DropdownButtonFormField<String>(initialValue:_scopeId,decoration:const InputDecoration(labelText:'Topic'),items:values.map((v)=>DropdownMenuItem(value:v.id,child:Text(v.name))).toList(),onChanged:(v)=>setState(()=>_scopeId=v))),
 if(_scope=='collection')ref.watch(collectionsProvider).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(values)=>DropdownButtonFormField<String>(initialValue:_scopeId,decoration:const InputDecoration(labelText:'Collection'),items:values.map((v)=>DropdownMenuItem(value:v.id,child:Text(v.name))).toList(),onChanged:(v)=>setState(()=>_scopeId=v))),
 const SizedBox(height:16),FilledButton(onPressed:_saving||(_scope=='selected'?_sources.isEmpty:_scopeId==null)?null:_create,child:Text(_saving?'Creating locally…':'Create derived snapshot')),
 ]));
}
class CompressionPage extends ConsumerWidget{
 const CompressionPage({super.key,required this.id});final String id;
 @override Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('Derived overview')),body:ref.watch(compressionProvider(id)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(c)=>ListView(padding:const EdgeInsets.all(16),children:[
 Text(c['title'] as String,style:Theme.of(context).textTheme.headlineSmall),Text('DERIVED EXTRACTIVE SNAPSHOT · generated ${knowledgeTime(c['generated_ts'])}'),
 Text('Scope: ${c['scope_kind']} · ${knowledgeStrings(c,'source_ids').length} source(s)'),
 if(knowledgeStrings(c,'stale_source_ids').isNotEmpty||c['scope_changed']==true||c['metadata_changed']==true)const Card(child:ListTile(leading:Icon(Icons.warning_amber),title:Text('Snapshot is stale'),subtitle:Text('Source content, source metadata/associations or scope membership has changed. Regenerate to refresh; the snapshot below is retained historical material.'))),
 Wrap(spacing:8,children:[FilledButton.tonal(onPressed:()async{if(await knowledgeConfirm(context,'Regenerate overview?','This replaces the derived snapshot using current local sources. Originals are untouched.')){if(!context.mounted){return;}await knowledgeChange(context,ref,(r)=>r.regenerateCompression(id));}},child:const Text('Regenerate')),OutlinedButton(onPressed:()async{if(!await knowledgeConfirm(context,'Discard derived overview?','Only this optional snapshot and its references are removed. Original sources remain saved.')){return;}if(!context.mounted){return;}final ok=await knowledgeChange(context,ref,(r)=>r.discardCompression(id));if(ok&&context.mounted){context.pop();}},child:const Text('Discard'))]),
 const ListTile(title:Text('Overview excerpts — not an exhaustive summary')),
 ...knowledgeRows(c,'excerpts').map(knowledgeQuote),
 ExpansionTile(title:const Text('Key concepts — stored topic associations'),children:knowledgeRows(c,'concepts').map((n)=>Column(children:[ListTile(title:Text(n['name'] as String),subtitle:Text('${n['count']} source(s); not a belief profile')),...knowledgeStrings(n,'source_ids').map((source)=>KnowledgeSourceButtons(id:source))])).toList()),
 ExpansionTile(title:const Text('Recurring entities — extracted candidates'),children:knowledgeRows(c,'entities').map((n)=>Column(children:[ListTile(title:Text(n['name'] as String),subtitle:Text('${n['count']} sources; extraction may be wrong')),...knowledgeStrings(n,'source_ids').map((source)=>KnowledgeSourceButtons(id:source))])).toList()),
 ExpansionTile(title:const Text('Timeline — dates retain their kinds'),children:knowledgeRows(c,'timeline').map((t)=>Column(children:[ListTile(title:Text('${knowledgeTime(t['ts'])} · ${t['kind']}'),subtitle:Text(t['note'] as String? ??'Recorded timestamp')),KnowledgeSourceButtons(id:t['item_id'] as String)])).toList()),
 ExpansionTile(title:const Text('Possible disagreements — stored links, not verified contradictions'),children:knowledgeRows(c,'disagreements').map((link)=>Card(child:Column(children:[knowledgeField('Recorded basis',link['basis']),Text('Heuristic score ${link['confidence']}; not truth probability'),KnowledgeSourceButtons(id:link['source_item_id'] as String),KnowledgeSourceButtons(id:link['target_item_id'] as String)]))).toList()),
 ExpansionTile(title:const Text('Literal question excerpts — not proven unresolved'),children:knowledgeRows(c,'questions').map(knowledgeQuote).toList()),
 ExpansionTile(title:const Text('All original references & snapshot fingerprints'),children:knowledgeStrings(c,'source_ids').map((source)=>Column(children:[knowledgeField('Stored block fingerprint',(c['source_hashes'] as Map)[source]),KnowledgeSourceButtons(id:source)])).toList()),knowledgeLimits(c),
 ])));
}
