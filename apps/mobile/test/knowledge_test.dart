import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/core/knowledge_models.dart';
import 'package:refract/core/models.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/knowledge/decision_page.dart';
import 'package:refract/features/knowledge/compression_page.dart';
import 'package:refract/features/knowledge/knowledge_map.dart';
import 'package:refract/features/knowledge/knowledge_widgets.dart';
import 'package:refract/features/knowledge/source_page.dart';

Map<String,dynamic> decisionJson()=>{'id':'d1','title':'Choose SQLite','context':'Local-first','options':['SQLite','Remote DB'],'selected_option':'SQLite','reasoning':'Offline operation','decision_ts':1700000000,'expected_outcome':'Local storage','review_ts':null,'project_id':null,'source_ids':['a'],'created_ts':1700000000,'updated_ts':1700000001,'archived':false,'kind':'user_recorded_decision'};
Map<String,dynamic> node(String kind,String id,String label)=>{'key':'$kind:$id','kind':kind,'id':id,'label':label,'ts':100,'source_item_id':kind=='document'?id:null,'block_idx':null,'detail':'Association, not a belief'};
Map<String,dynamic> overview()=>{'id':'c1','title':'Privacy overview','scope_kind':'selected','source_ids':['a'],'generated_ts':100,'stale_source_ids':['a'],'scope_changed':false,'metadata_changed':false,'excerpts':[{'item_id':'a','title':'Privacy source','block_idx':3,'quote':'Exact saved source excerpt.'}],'concepts':[],'entities':[],'timeline':[],'disagreements':[],'questions':[],'source_hashes':{'a':'block-hash'},'limitations':['Originals remain independent.']};
class _FakeRepository implements RefractRepository{
 Map<String,dynamic>? saved;String? discarded;
 @override DecisionRecord saveDecision(Map<String,dynamic> input){saved=input;return DecisionRecord.fromJson({...decisionJson(),...input,'id':'d1'});}
 @override void discardCompression(String id){discarded=id;}
 @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
void main(){
 test('Knowledge DTOs preserve explicit decision state and graph relationship evidence',(){
  final d=DecisionRecord.fromJson(decisionJson());expect(d.kind,'user_recorded_decision');expect(d.options,['SQLite','Remote DB']);expect(d.reviewTs,isNull);expect(d.sourceIds,['a']);
  final graph=KnowledgeGraph.fromJson({'focus':node('document','a','Source A'),'nodes':[node('document','b','Source B')],'edges':[{'source_key':'document:a','target_key':'document:b','kind':'follow_up','basis':'User marked follow-up','confidence':0.6,'relationship_id':'r1'}],'next_offset':20,'explanation':'Bounded navigation'});
  expect(graph.nextOffset,20);expect(graph.edges.single.relationshipId,'r1');expect(graph.edges.single.basis,'User marked follow-up');expect(graph.edges.single.confidence,0.6);
  final recall=RecallResponse.fromJson({'query':'Why SQLite','mode':'answer','answer':'User-recorded reason','answer_kind':'user_recorded_decision','model_used':false,'encoder':'none','hits':[],'connections':[],'timeline':[],'limitations':[],'scanned_items':0,'decision_records':[decisionJson()]});expect(recall.decisionRecords.single.reasoning,'Offline operation');
 });
 test('Calendar filters reject normalized invalid dates and retain UTC boundaries',(){expect(knowledgeDate('2026-02-31'),isNull);expect(knowledgeDate('2026-13-01'),isNull);expect(knowledgeDate('2026-1-01'),isNull);expect(knowledgeDate('2028-02-29'),isNotNull);expect(knowledgeDay(knowledgeDate('2026-11-06')!),'2026-11-06');});
 testWidgets('Decision creation requires an explicit save with choice, reasoning and date',(tester)async{
  final fake=_FakeRepository();final router=GoRouter(routes:[GoRoute(path:'/',builder:(_,s)=>const DecisionEditorPage()),GoRoute(path:'/knowledge/decision/:id',builder:(_,s)=>const Scaffold(body:Text('Saved explicit decision')))]);addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>fake),projectsProvider.overrideWith((ref)async=>[])],child:MaterialApp.router(routerConfig:router)));await tester.pumpAndSettle();expect(fake.saved,isNull);
  Future<void> fill(String label,String text)async{final f=find.widgetWithText(TextFormField,label);await tester.scrollUntilVisible(f.hitTestable(),120,scrollable:find.byType(Scrollable).first);await tester.enterText(f,text);tester.testTextInput.hide();await tester.pumpAndSettle();}
  await fill('Title','Choose SQLite');await fill('Context','Local-first');await fill('Options (one per line)','SQLite\nRemote DB');await fill('Reasoning','Offline operation');await fill('Expected outcome','Local storage');
  await tester.scrollUntilVisible(find.text('Selected option').hitTestable(),120,scrollable:find.byType(Scrollable).first);await tester.tap(find.byType(DropdownButtonFormField<String>).first);await tester.pumpAndSettle();await tester.tap(find.text('SQLite').last);await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Save user-recorded decision').hitTestable(),120,scrollable:find.byType(Scrollable).first);expect(fake.saved,isNull);await tester.tap(find.text('Save user-recorded decision'));await tester.pumpAndSettle();expect(fake.saved?['reasoning'],'Offline operation');expect(fake.saved?['selected_option'],'SQLite');expect(fake.saved?['decision_ts'],isA<int>());expect(find.text('Saved explicit decision'),findsOneWidget);
 });
 testWidgets('Graph pagination and expansion issue bounded requests, not an eager full graph',(tester)async{
  final requests=<Map<String,dynamic>>[];
  await tester.pumpWidget(ProviderScope(overrides:[knowledgeGraphProvider.overrideWith((ref,q)async{final request=jsonDecode(q) as Map<String,dynamic>;requests.add(request);final root=request['kind']=='library';return KnowledgeGraph.fromJson({'focus':node(root?'library':'document',root?'':'b',root?'Stored knowledge':'Source B'),'nodes':root?[node('document','b','Source B')]:[],'edges':[],'next_offset':root&&request['offset']==0?20:null,'explanation':'One-hop window; suggestions are not proof.'});})],child:const MaterialApp(home:Scaffold(body:KnowledgeMapPanel()))));await tester.pumpAndSettle();expect(requests.single['limit'],20);expect(requests.single['offset'],0);
  await tester.ensureVisible(find.text('Next page'));await tester.tap(find.text('Next page'));await tester.pumpAndSettle();expect(requests.last['offset'],20);
  await tester.ensureVisible(find.text('Expand node'));await tester.tap(find.text('Expand node'));await tester.pumpAndSettle();expect(requests.last['kind'],'document');expect(requests.last['id'],'b');expect(requests.last['offset'],0);
 });
 testWidgets('Derived overview is labeled stale and opens an exact cited block',(tester)async{
  final router=GoRouter(routes:[GoRoute(path:'/',builder:(_,s)=>const CompressionPage(id:'c1')),GoRoute(path:'/reader/:id',builder:(_,s)=>Scaffold(body:Text('Source ${s.pathParameters['id']} block ${s.uri.queryParameters['block']}')))]);addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides:[compressionProvider.overrideWith((ref,id)async=>overview())],child:MaterialApp.router(routerConfig:router)));await tester.pumpAndSettle();expect(find.text('Snapshot is stale'),findsOneWidget);expect(find.textContaining('DERIVED EXTRACTIVE SNAPSHOT'),findsOneWidget);
  await tester.scrollUntilVisible(find.text('Open source').hitTestable(),100,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('Open source'));await tester.pumpAndSettle();expect(find.text('Source a block 3'),findsOneWidget);
 });
 testWidgets('Discarding compression requires confirmation and removes only the derived ID',(tester)async{
  final fake=_FakeRepository();final router=GoRouter(routes:[GoRoute(path:'/',builder:(context,s)=>Scaffold(body:TextButton(onPressed:()=>context.push('/overview'),child:const Text('Original sources remain')))),GoRoute(path:'/overview',builder:(_,s)=>const CompressionPage(id:'c1'))]);addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>fake),compressionProvider.overrideWith((ref,id)async=>overview())],child:MaterialApp.router(routerConfig:router)));await tester.tap(find.text('Original sources remain'));await tester.pumpAndSettle();await tester.tap(find.text('Discard'));await tester.pumpAndSettle();expect(fake.discarded,isNull);await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(fake.discarded,isNull);await tester.tap(find.text('Discard'));await tester.pumpAndSettle();await tester.tap(find.text('Confirm'));await tester.pumpAndSettle();expect(fake.discarded,'c1');expect(find.text('Original sources remain'),findsOneWidget);
 });
 testWidgets('Legacy source history is unavailable, not invented processing events',(tester)async{
  await tester.pumpWidget(ProviderScope(overrides:[sourceIntelligenceProvider.overrideWith((ref,id)async=>{'title':'Old source','source_url':null,'capture_method':'text','captured_ts':100,'author':null,'language':null,'extraction_confidence':0.5,'timestamps':[],'history':[],'artifacts':[],'annotations':[],'decision_ids':[],'versions':[],'limitations':[]})],child:const MaterialApp(home:SourceIntelligencePage(id:'a'))));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.textContaining('Legacy processing details are unavailable.').hitTestable(),150,scrollable:find.byType(Scrollable).first);expect(find.textContaining('Legacy processing details are unavailable.'),findsOneWidget);expect(find.textContaining('not reconstructed extraction'),findsOneWidget);
 });
}
