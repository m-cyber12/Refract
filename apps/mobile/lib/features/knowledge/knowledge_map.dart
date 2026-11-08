import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/knowledge_models.dart';
import '../../core/repository.dart';
import 'knowledge_widgets.dart';

class KnowledgeMapPage extends StatelessWidget{
 const KnowledgeMapPage({super.key,this.kind='library',this.id=''});final String kind,id;
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Knowledge Map')),body:KnowledgeMapPanel(kind:kind,id:id));
}
class KnowledgeMapPanel extends ConsumerStatefulWidget{
 const KnowledgeMapPanel({super.key,this.kind='library',this.id=''});final String kind,id;
 @override ConsumerState<KnowledgeMapPanel> createState()=>_KnowledgeMapPanelState();
}
class _KnowledgeMapPanelState extends ConsumerState<KnowledgeMapPanel>{
 late String _kind,_id;String _category='';int _offset=0;int? _after,_before;
 final _afterText=TextEditingController(),_beforeText=TextEditingController();
 final _trail=<KnowledgeNode>[];
 @override void initState(){super.initState();_kind=widget.kind;_id=widget.id;}
 @override void dispose(){_afterText.dispose();_beforeText.dispose();super.dispose();}
 void _expand(KnowledgeNode node,KnowledgeNode focus)=>setState((){_trail.add(focus);_kind=node.kind;_id=node.id;_offset=0;});
 void _filter(){final a=_afterText.text,b=_beforeText.text;final after=a.isEmpty?null:knowledgeDate(a);final dayEnd=b.isEmpty?null:knowledgeDate(b);if(a.isNotEmpty&&after==null||b.isNotEmpty&&dayEnd==null||after!=null&&dayEnd!=null&&after>dayEnd){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Use valid UTC dates in ascending order (YYYY-MM-DD).')));return;}setState((){_after=after;_before=dayEnd==null?null:dayEnd+86399;_offset=0;});}
 Future<void> _edge(KnowledgeEdge edge)async{
 await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text(edge.kind.replaceAll('_',' '),style:Theme.of(ctx).textTheme.titleLarge),knowledgeField('From / to','${edge.sourceKey}\n${edge.targetKey}'),knowledgeField('Recorded basis',edge.basis),Text(edge.relationshipId==null?'Stored association / navigation membership. Not a factual claim.':'Suggested or user-asserted relationship · heuristic score ${edge.confidence.toStringAsFixed(2)} is not a truth probability.'),
 if(edge.relationshipId!=null)OutlinedButton.icon(onPressed:()async{if(!await knowledgeConfirm(ctx,'Dismiss this relationship?','The original sources remain unchanged. This suggestion will not be shown in the graph or path explorer.')){return;}if(!ctx.mounted){return;}final ok=await knowledgeChange(ctx,ref,(r)=>r.dismissKnowledgeLink(edge.relationshipId!));if(ok&&ctx.mounted){Navigator.pop(ctx);}},icon:const Icon(Icons.link_off),label:const Text('Dismiss incorrect relationship')),
 ]))));
 }
 @override Widget build(BuildContext context){final request=jsonEncode({'kind':_kind,'id':_id,'category':_category.isEmpty?null:_category,'after':_after,'before':_before,'offset':_offset,'limit':20});
 return ListView(padding:const EdgeInsets.all(16),children:[
 const Text('Expand a node to load one-hop neighbors. This map combines explicit associations with labeled suggestions; proximity and paths are not proof.'),
 Wrap(spacing:8,children:[OutlinedButton(onPressed:()=>setState((){_kind='library';_id='';_offset=0;_trail.clear();}),child:const Text('Library root')),if(_trail.isNotEmpty)TextButton.icon(onPressed:()=>setState((){final n=_trail.removeLast();_kind=n.kind;_id=n.id;_offset=0;}),icon:const Icon(Icons.arrow_back),label:const Text('Previous focus')),TextButton(onPressed:()=>context.push('/knowledge/path'),child:const Text('Explore relationship paths'))]),
 DropdownButtonFormField<String>(initialValue:_category,decoration:const InputDecoration(labelText:'Neighbor category'),items:['','document','topic','project','entity','note','event','decision'].map((v)=>DropdownMenuItem(value:v,child:Text(v.isEmpty?'All categories':v))).toList(),onChanged:(v)=>setState((){_category=v??'';_offset=0;})),
 Row(children:[Expanded(child:TextField(controller:_afterText,decoration:const InputDecoration(labelText:'From UTC date',hintText:'YYYY-MM-DD'))),const SizedBox(width:8),Expanded(child:TextField(controller:_beforeText,decoration:const InputDecoration(labelText:'Through UTC date',hintText:'YYYY-MM-DD')))]),TextButton(onPressed:_filter,child:const Text('Apply date filter')),
 const Text('Date kinds differ: documents use capture time; events use event date; decisions use the recorded decision date. Filters apply to neighbors, not the focus.'),
 ref.watch(knowledgeGraphProvider(request)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(graph)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text(graph.focus.label,style:Theme.of(context).textTheme.titleLarge),Text('${graph.focus.kind} · ${graph.focus.detail}'),
 _NodeMap(focus:graph.focus,nodes:graph.nodes.take(8).toList(),onExpand:(n)=>_expand(n,graph.focus)),
 if(graph.nodes.length>8)Text('First 8 nodes drawn; all ${graph.nodes.length} nodes in this page are listed below.'),
 if(graph.nodes.isEmpty)const ListTile(title:Text('No neighbors in this filtered window.')),
 ...graph.nodes.map((node)=>Card(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[ListTile(title:Text(node.label),subtitle:Text('${node.kind} · ${knowledgeTime(node.ts)}\n${node.detail}'),trailing:const Icon(Icons.hub_outlined),onTap:()=>_expand(node,graph.focus)),Wrap(children:[TextButton(onPressed:()=>_expand(node,graph.focus),child:const Text('Expand node')),if(node.kind=='decision')TextButton(onPressed:()=>context.push('/knowledge/decision/${node.id}'),child:const Text('Open decision')),if(node.kind=='project')TextButton(onPressed:()=>context.push('/memory/project/${node.id}'),child:const Text('Open project')),if(node.sourceItemId!=null)KnowledgeSourceButtons(id:node.sourceItemId!,blockIdx:node.blockIdx)]),...graph.edges.where((e)=>e.sourceKey==node.key||e.targetKey==node.key).map((e)=>ListTile(dense:true,leading:const Icon(Icons.link),title:Text(e.kind.replaceAll('_',' ')),subtitle:Text(e.relationshipId==null?'Association / navigation membership':'Suggestion or user assertion — inspect basis'),onTap:()=>_edge(e)))]))),
 Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[TextButton(onPressed:_offset==0?null:()=>setState(()=>_offset=math.max(0,_offset-20)),child:const Text('Previous page')),Text('Offset $_offset'),TextButton(onPressed:graph.nextOffset==null?null:()=>setState(()=>_offset=graph.nextOffset!),child:const Text('Next page'))]),
 Text(graph.explanation,style:Theme.of(context).textTheme.bodySmall),
 if(graph.focus.sourceItemId!=null)KnowledgeSourceButtons(id:graph.focus.sourceItemId!,blockIdx:graph.focus.blockIdx),
 ])),
 ]);
 }
}
class _NodeMap extends StatelessWidget{
 const _NodeMap({required this.focus,required this.nodes,required this.onExpand});final KnowledgeNode focus;final List<KnowledgeNode> nodes;final ValueChanged<KnowledgeNode> onExpand;
 @override Widget build(BuildContext context)=>SizedBox(height:340,child:LayoutBuilder(builder:(context,constraints){final center=Offset(constraints.maxWidth/2,170);final radius=math.min(constraints.maxWidth*.35,125.0);final points=[for(var i=0;i<nodes.length;i++)center+Offset(math.cos(i*math.pi*2/nodes.length-math.pi/2)*radius,math.sin(i*math.pi*2/nodes.length-math.pi/2)*radius)];
 return CustomPaint(painter:_MapLines(center,points,Theme.of(context).colorScheme.outlineVariant),child:Stack(children:[Positioned(left:center.dx-48,top:center.dy-28,width:96,height:56,child:Tooltip(message:focus.label,child:Card(color:Theme.of(context).colorScheme.primaryContainer,child:Center(child:Padding(padding:const EdgeInsets.all(4),child:Text(focus.label,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center)))))),for(var i=0;i<nodes.length;i++)Positioned(left:points[i].dx-40,top:points[i].dy-26,width:80,height:52,child:Tooltip(message:'${nodes[i].kind}: ${nodes[i].label}',child:Semantics(label:'Expand ${nodes[i].kind}: ${nodes[i].label}',button:true,child:Card(child:InkWell(onTap:()=>onExpand(nodes[i]),child:Center(child:Padding(padding:const EdgeInsets.all(4),child:Text(nodes[i].label,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center))))))))]));
 }));
}
class _MapLines extends CustomPainter{
 _MapLines(this.center,this.points,this.color);final Offset center;final List<Offset> points;final Color color;
 @override void paint(Canvas canvas,Size size){final pen=Paint()..color=color..strokeWidth=1;for(final point in points){canvas.drawLine(center,point,pen);}}
 @override bool shouldRepaint(covariant _MapLines oldDelegate)=>true;
}
class KnowledgePathPage extends ConsumerStatefulWidget{
 const KnowledgePathPage({super.key});
 @override ConsumerState<KnowledgePathPage> createState()=>_KnowledgePathPageState();
}
class _KnowledgePathPageState extends ConsumerState<KnowledgePathPage>{
 List<String> _sources=[];int _depth=3;String? _request;
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Relationship paths')),body:ListView(padding:const EdgeInsets.all(16),children:[
 const Text('Choose exactly two sources. Traversal treats stored links as undirected associations, not logical entailment. No path found does not prove no connection exists.'),
 KnowledgeSourcePicker(selected:_sources,onChanged:(v)=>setState((){_sources=v;_request=null;})),DropdownButtonFormField<int>(initialValue:_depth,decoration:const InputDecoration(labelText:'Maximum hops'),items:[1,2,3,4].map((v)=>DropdownMenuItem(value:v,child:Text('$v'))).toList(),onChanged:(v)=>setState((){_depth=v??3;_request=null;})),
 FilledButton(onPressed:_sources.length!=2?null:()=>setState(()=>_request=jsonEncode({'from_id':_sources[0],'to_id':_sources[1],'max_depth':_depth})),child:const Text('Find bounded path')),
 if(_request!=null)ref.watch(knowledgePathProvider(_request!)).when(loading:knowledgeLoading,error:(e,_)=>knowledgeError(e),data:(path)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(path['found']==true?'Stored link path found':'No path in this bounded search'),if(path['limited']==true)const Text('Search hit a safety limit — results are incomplete.'),...knowledgeRows(path,'steps').map((s)=>Card(child:Column(children:[knowledgeField(s['kind'] as String,s['basis']),knowledgeField('Original stored edge direction','${s['original_source_id']} → ${s['original_target_id']}'),Text('Heuristic score ${s['confidence']} — not truth probability'),KnowledgeSourceButtons(id:s['from_id'] as String),const Icon(Icons.link),KnowledgeSourceButtons(id:s['to_id'] as String),TextButton(onPressed:()async{if(await knowledgeConfirm(context,'Dismiss this relationship?','The source documents will not be changed.')){if(!context.mounted){return;}await knowledgeChange(context,ref,(r)=>r.dismissKnowledgeLink(s['relationship_id'] as String));}},child:const Text('Dismiss link'))]))),Text(path['explanation'] as String)])),
 ]));
}
