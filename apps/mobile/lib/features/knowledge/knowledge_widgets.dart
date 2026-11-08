import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/repository.dart';

String knowledgeTime(dynamic ts)=>ts is num?'${DateTime.fromMillisecondsSinceEpoch(ts.toInt()*1000,isUtc:true).toIso8601String().split('.').first} UTC':'Not recorded';
List<Map<String,dynamic>> knowledgeRows(Map<String,dynamic> value,String key)=>((value[key] as List?)??[]).cast<Map<String,dynamic>>();
List<String> knowledgeStrings(Map<String,dynamic> value,String key)=>((value[key] as List?)??[]).cast<String>();
Widget knowledgeError(Object error)=>Padding(padding:const EdgeInsets.all(16),child:SelectableText('$error'));
Widget knowledgeLoading()=>const Center(child:Padding(padding:EdgeInsets.all(24),child:CircularProgressIndicator()));
void invalidateKnowledge(WidgetRef ref){
  ref.invalidate(decisionsProvider);ref.invalidate(decisionProvider);ref.invalidate(decisionHistoryProvider);
  ref.invalidate(knowledgeGraphProvider);ref.invalidate(knowledgePathProvider);
  ref.invalidate(compressionsProvider);ref.invalidate(compressionProvider);
  ref.invalidate(sourceIntelligenceProvider);ref.invalidate(sourceDiffProvider);
  ref.invalidate(recallProvider);ref.invalidate(dailySignalProvider);
}
Future<bool> knowledgeChange(BuildContext context,WidgetRef ref,void Function(RefractRepository) action)async{
 try{final repo=await ref.read(bootstrapProvider.future);action(repo);invalidateKnowledge(ref);return true;}
 catch(e){if(context.mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}return false;}
}
Future<bool> knowledgeConfirm(BuildContext context,String title,String detail)async=>await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:Text(detail),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]))??false;
class KnowledgeSourceButtons extends StatelessWidget{
 const KnowledgeSourceButtons({super.key,required this.id,this.blockIdx});
 final String id;final int? blockIdx;
 @override Widget build(BuildContext context)=>Wrap(spacing:8,children:[
 TextButton.icon(onPressed:()=>context.push('/reader/${Uri.encodeComponent(id)}${blockIdx==null?'':'?block=$blockIdx'}'),icon:const Icon(Icons.article_outlined),label:const Text('Open source')),
 TextButton(onPressed:()=>context.push('/knowledge/source/${Uri.encodeComponent(id)}'),child:const Text('Source intelligence')),
 ]);
}
class KnowledgeSourcePicker extends ConsumerWidget{
 const KnowledgeSourcePicker({super.key,required this.selected,required this.onChanged});
 final List<String> selected;final ValueChanged<List<String>> onChanged;
 Future<void> _pick(BuildContext context,WidgetRef ref)async{
  try{final repo=await ref.read(bootstrapProvider.future);final items=repo.listItems(limit:200);if(!context.mounted){return;}
   final chosen=selected.toSet();var search='';final result=await showDialog<List<String>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setState)=>AlertDialog(title:Text('Choose sources (${chosen.length}/30; first 200 captures)'),content:SizedBox(width:480,height:400,child:Column(children:[TextField(decoration:const InputDecoration(labelText:'Filter sources by title'),onChanged:(v)=>setState(()=>search=v.toLowerCase())),Expanded(child:ListView(children:items.where((i)=>i.displayTitle.toLowerCase().contains(search)).map((i)=>CheckboxListTile(value:chosen.contains(i.id),title:Text(i.displayTitle),onChanged:(v)=>setState((){if(v==true&&chosen.length<30){chosen.add(i.id);}if(v==false){chosen.remove(i.id);}}))).toList()))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,chosen.toList()),child:const Text('Use selected'))])));
   if(result!=null){onChanged(result);}
  }catch(e){if(context.mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}}
 }
 @override Widget build(BuildContext context,WidgetRef ref)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[OutlinedButton.icon(onPressed:()=>_pick(context,ref),icon:const Icon(Icons.library_add_check_outlined),label:Text('Choose sources (${selected.length}/30)')), ...selected.map((id)=>ref.watch(itemProvider(id)).when(data:(item)=>ListTile(dense:true,title:Text(item?.displayTitle??'Source no longer available'),trailing:IconButton(tooltip:'Remove source',icon:const Icon(Icons.close),onPressed:()=>onChanged(selected.where((v)=>v!=id).toList()))),loading:()=>Text(id),error:(e,_)=>Text('$id · $e')))]);
}
class KnowledgeProjectPicker extends ConsumerWidget{
 const KnowledgeProjectPicker({super.key,required this.value,required this.onChanged});
 final String? value;final ValueChanged<String?> onChanged;
 @override Widget build(BuildContext context,WidgetRef ref)=>ref.watch(projectsProvider).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(projects)=>DropdownButtonFormField<String>(initialValue:value,decoration:const InputDecoration(labelText:'Project association'),items:[const DropdownMenuItem<String>(value:null,child:Text('No project')),...projects.map((p)=>DropdownMenuItem(value:p.id,child:Text(p.name)))],onChanged:onChanged));
}
Widget knowledgeLimits(Map<String,dynamic> data)=>ExpansionTile(title:const Text('Limitations & evidence quality'),children:knowledgeStrings(data,'limitations').map((t)=>ListTile(title:Text(t))).toList());
Widget knowledgeField(String label,dynamic value)=>ListTile(title:Text(label),subtitle:SelectableText(value?.toString()??'Not recorded'));
Widget knowledgeQuote(Map<String,dynamic> q)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${q['title']} · VERBATIM EXCERPT · block ${q['block_idx']}'),SelectableText(q['quote'] as String),KnowledgeSourceButtons(id:q['item_id'] as String,blockIdx:(q['block_idx'] as num).toInt())])));

String knowledgeDay(int ts)=>DateTime.fromMillisecondsSinceEpoch(ts*1000,isUtc:true).toIso8601String().substring(0,10);
int? knowledgeDate(String input){
 if(!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)){return null;}
 final date=DateTime.tryParse('${input}T00:00:00Z');
 if(date==null||date.toIso8601String().substring(0,10)!=input){return null;}
 return date.millisecondsSinceEpoch~/1000;
}
