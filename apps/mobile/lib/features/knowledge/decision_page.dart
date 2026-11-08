import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/knowledge_models.dart';
import '../../core/repository.dart';
import 'knowledge_widgets.dart';

class DecisionsPanel extends ConsumerStatefulWidget{
 const DecisionsPanel({super.key,this.projectId});final String? projectId;
 @override ConsumerState<DecisionsPanel> createState()=>_DecisionsPanelState();
}
class _DecisionsPanelState extends ConsumerState<DecisionsPanel>{
 String _query='';bool _archived=false;String? _project;
 @override void initState(){super.initState();_project=widget.projectId;}
 @override Widget build(BuildContext context){
 final request=jsonEncode({'query':_query,'project_id':_project,'include_archived':_archived});
 return ListView(padding:const EdgeInsets.all(16),children:[
 const Text('Explicit decisions only. Imported text and AI suggestions are never promoted to confirmed decisions. Search covers the latest 1,000 records and returns up to 100 matches.'),
 const SizedBox(height:12),FilledButton.icon(onPressed:()=>context.push('/knowledge/new${_project==null?'':'?project=${Uri.encodeComponent(_project!)}'}'),icon:const Icon(Icons.add),label:const Text('Record a decision')),
 TextField(decoration:const InputDecoration(labelText:'Search title, context, choice or reasoning'),onSubmitted:(v)=>setState(()=>_query=v)),
 KnowledgeProjectPicker(value:_project,onChanged:(v)=>setState(()=>_project=v)),
 SwitchListTile(title:const Text('Include archived decisions'),value:_archived,onChanged:(v)=>setState(()=>_archived=v)),
 ref.watch(decisionsProvider(request)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(records)=>Column(children:[if(records.isEmpty)const ListTile(title:Text('No recorded decisions match.')),...records.map((d)=>Card(child:ListTile(title:Text(d.title),subtitle:Text('${d.archived?'ARCHIVED · ':''}${knowledgeTime(d.decisionTs)}\nSelected: ${d.selectedOption}\n${d.reasoning}'),onTap:()=>context.push('/knowledge/decision/${d.id}'))))])),
 ]);
 }
}
class DecisionPage extends ConsumerWidget{
 const DecisionPage({super.key,required this.id});final String id;
 @override Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('Decision Memory')),body:ref.watch(decisionProvider(id)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(d)=>ListView(padding:const EdgeInsets.all(16),children:[
 Text(d.title,style:Theme.of(context).textTheme.headlineSmall),Text('USER-RECORDED DECISION${d.archived?' · ARCHIVED':''}'),
 Wrap(spacing:8,children:[FilledButton.tonal(onPressed:()=>context.push('/knowledge/edit/${d.id}'),child:const Text('Edit decision')),OutlinedButton(onPressed:()async{if(await knowledgeConfirm(context,d.archived?'Restore decision?':'Archive decision?','Original sources and revision history are kept.')){if(!context.mounted)return;await knowledgeChange(context,ref,(r)=>r.archiveDecision(id,!d.archived));}},child:Text(d.archived?'Restore':'Archive')),TextButton(onPressed:()=>context.push('/knowledge/map?kind=decision&id=${Uri.encodeComponent(d.id)}'),child:const Text('Explore connections'))]),
 knowledgeField('Decision date',knowledgeTime(d.decisionTs)),knowledgeField('Context',d.context),knowledgeField('Options considered',d.options.join('\n')),knowledgeField('Selected option',d.selectedOption),knowledgeField('Reasoning',d.reasoning),knowledgeField('Expected outcome',d.expectedOutcome),knowledgeField('Review date',knowledgeTime(d.reviewTs)),
 if(d.projectId!=null)ref.watch(projectsProvider).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(projects)=>ListTile(title:const Text('Associated project'),subtitle:Text(projects.where((p)=>p.id==d.projectId).map((p)=>p.name).firstOrNull??d.projectId!),onTap:()=>context.push('/memory/project/${d.projectId}'))),
 const ListTile(title:Text('Linked sources — references, not proof that the decision is correct')),
 ...d.sourceIds.map((id)=>ref.watch(itemProvider(id)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(item)=>Card(child:Column(children:[ListTile(title:Text(item?.displayTitle??id)),KnowledgeSourceButtons(id:id)])))),
 ExpansionTile(title:const Text('Revision history (latest 100)'),children:[ref.watch(decisionHistoryProvider(id)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(history)=>Column(children:history.map((v)=>ExpansionTile(title:Text(knowledgeTime(v.updatedTs)),subtitle:Text(v.archived?'Archived':'User-recorded snapshot'),children:[knowledgeField('Title',v.title),knowledgeField('Context',v.context),knowledgeField('Options',v.options.join('\n')),knowledgeField('Selected',v.selectedOption),knowledgeField('Reasoning',v.reasoning),knowledgeField('Expected outcome',v.expectedOutcome),knowledgeField('Decision / review dates','${knowledgeTime(v.decisionTs)} / ${knowledgeTime(v.reviewTs)}'),knowledgeField('Project',v.projectId),...v.sourceIds.map((source)=>KnowledgeSourceButtons(id:source))])).toList()))]),
 ])));
}
class DecisionEditorPage extends ConsumerWidget{
 const DecisionEditorPage({super.key,this.id,this.projectId,this.sourceId});final String? id,projectId,sourceId;
 @override Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:Text(id==null?'Record decision':'Edit decision')),body:id==null?_DecisionForm(projectId:projectId,sourceId:sourceId):ref.watch(decisionProvider(id!)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(d)=>_DecisionForm(key:ValueKey(d.id),record:d)));
}
class _DecisionForm extends ConsumerStatefulWidget{
 const _DecisionForm({super.key,this.record,this.projectId,this.sourceId});final DecisionRecord? record;final String? projectId,sourceId;
 @override ConsumerState<_DecisionForm> createState()=>_DecisionFormState();
}
class _DecisionFormState extends ConsumerState<_DecisionForm>{
 final _form=GlobalKey<FormState>();
 late final Map<String,TextEditingController> _fields;
 late List<String> _sources;String? _project,_selected;bool _saving=false;
 @override void initState(){super.initState();final d=widget.record;_fields={for(final e in <String,String>{'Title':d?.title??'','Context':d?.context??'','Options (one per line)':d?.options.join('\n')??'','Reasoning':d?.reasoning??'','Expected outcome':d?.expectedOutcome??'','Decision date (YYYY-MM-DD, UTC)':knowledgeDay(d?.decisionTs??DateTime.now().toUtc().millisecondsSinceEpoch~/1000),'Review date (optional, YYYY-MM-DD, UTC)':d?.reviewTs==null?'':knowledgeDay(d!.reviewTs!)}.entries)e.key:TextEditingController(text:e.value)};_sources=[...?d?.sourceIds,if(d==null&&widget.sourceId!=null)widget.sourceId!];_project=d?.projectId??widget.projectId;_selected=d?.selectedOption;}
 @override void dispose(){for(final c in _fields.values)c.dispose();super.dispose();}
 List<String> get _options=>_fields['Options (one per line)']!.text.split('\n').map((s)=>s.trim()).where((s)=>s.isNotEmpty).toSet().toList();
 Future<void> _save()async{
 if(!_form.currentState!.validate())return;
 setState(()=>_saving=true);final d=widget.record;
 final day=_fields['Decision date (YYYY-MM-DD, UTC)']!.text;
 final review=_fields['Review date (optional, YYYY-MM-DD, UTC)']!.text;
 String? saved;
 final ok=await knowledgeChange(context,ref,(r){saved=r.saveDecision({'id':d?.id,'title':_fields['Title']!.text,'context':_fields['Context']!.text,'options':_options,'selected_option':_selected,'reasoning':_fields['Reasoning']!.text,'decision_ts':d!=null&&day==knowledgeDay(d.decisionTs)?d.decisionTs:knowledgeDate(day),'expected_outcome':_fields['Expected outcome']!.text,'review_ts':review.isEmpty?null:(d?.reviewTs!=null&&review==knowledgeDay(d!.reviewTs!)?d.reviewTs:knowledgeDate(review)),'project_id':_project,'source_ids':_sources}).id;});
 if(!mounted)return;setState(()=>_saving=false);if(ok)context.replace('/knowledge/decision/$saved');
 }
 @override Widget build(BuildContext context)=>Form(key:_form,child:ListView(padding:const EdgeInsets.all(16),children:[
 const Text('Record what you chose and why. Saving creates a user-authored decision, never an inferred one. Edits keep revision snapshots.'),
 ..._fields.entries.map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:8),child:TextFormField(controller:e.value,decoration:InputDecoration(labelText:e.key),maxLines:e.key=='Context'||e.key=='Reasoning'||e.key.startsWith('Options')?3:1,onChanged:e.key.startsWith('Options')?(v)=>setState((){if(!_options.contains(_selected))_selected=null;}):null,validator:(v){final text=v??'';if(e.key.startsWith('Review date')&&text.isEmpty)return null;if(e.key.contains('date'))return knowledgeDate(text)==null?'Use a valid UTC date, YYYY-MM-DD':null;if(text.trim().isEmpty)return 'Required';return null;}))),
 DropdownButtonFormField<String>(value:_options.contains(_selected)?_selected:null,isExpanded:true,decoration:const InputDecoration(labelText:'Selected option'),items:_options.map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>_selected=v),validator:(v)=>v==null?'Select one of the options considered':null),
 KnowledgeProjectPicker(value:_project,onChanged:(v)=>setState(()=>_project=v)),const SizedBox(height:12),KnowledgeSourcePicker(selected:_sources,onChanged:(v)=>setState(()=>_sources=v)),
 const SizedBox(height:20),FilledButton(onPressed:_saving?null:_save,child:Text(_saving?'Saving locally…':'Save user-recorded decision')),
 ]));
}
