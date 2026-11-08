import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/core/consumer_models.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/xray/consumer_page.dart';

Map<String,dynamic> claimJson({String id='c1',String item='a'})=>{'id':id,'item_id':item,'block_idx':3,'category':'receipt','field':'receipt_total','value':'29.99','value_type':'money','amount_minor':2999,'currency':'EUR','date_ts':null,'quote':'Total: EUR 29.99','start_byte':0,'end_byte':16,'confidence':0.75,'extracted_ts':100,'extractor_version':'consumer-rules-v1','source_text_sha256':'abc','status':'unconfirmed','source_matches':true};
ConsumerDocument doc()=>ConsumerDocument.fromJson({'item_id':'a','title':'Receipt A','source_url':'https://example.org/a','captured_ts':100,'original_sha256':'original-hash','claims':[claimJson()],'scanned':true,'truncated':false,'limitations':['Quotes describe source text; no legal verification.']});
class _FakeRepo implements RefractRepository{
  String? reviewed;int tracked=0;
  @override void consumerReview(String id,String status){reviewed='$id:$status';}
  @override ConsumerOriginalCheck consumerCheckOriginal(String id)=>ConsumerOriginalCheck(itemId:id,status:'unchanged_relative_to_recorded_hash',recordedSha256:'original-hash',explanation:'A matching hash does not prove authenticity.');
  @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
void main(){
  test('Consumer JSON preserves structured money, evidence ranges and review state',(){
    final c=ConsumerClaim.fromJson(claimJson());expect(c.amountMinor,2999);expect(c.currency,'EUR');expect(c.dateTs,isNull);expect(c.sourceMatches,true);expect(c.status,'unconfirmed');expect(c.blockIdx,3);
    expect(doc().claims.single.quote,'Total: EUR 29.99');
    final comparison=ConsumerComparison.fromJson({'item_ids':['a','b'],'fields':[{'field':'receipt_total','result':'different_extracted_values','claims':[claimJson(),claimJson(id:'c2',item:'b')],'missing_item_ids':[]}],'explanation':'Different sources may concern different purchases.'});expect(comparison.fields.single.claims.length,2);
  });

  testWidgets('Candidate review is explicit and supporting evidence opens the cited source block',(tester)async{
    final fake=_FakeRepo();final router=GoRouter(routes:[GoRoute(path:'/',builder:(_,state)=>const ConsumerDocumentPage(itemId:'a')),GoRoute(path:'/reader/:id',builder:(_,state)=>Scaffold(body:Text('Source ${state.pathParameters['id']} block ${state.uri.queryParameters['block']}')))]);addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>fake),consumerDocumentProvider.overrideWith((ref,id)async=>doc())],child:MaterialApp.router(routerConfig:router)));await tester.pumpAndSettle();
    expect(find.text('UNCONFIRMED EXTRACTION'),findsOneWidget);expect(fake.reviewed,isNull);expect(fake.tracked,0);
    await tester.scrollUntilVisible(find.text('Confirm extraction').hitTestable(),150,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.text('Confirm extraction'));await tester.pumpAndSettle();expect(fake.reviewed,'c1:user_confirmed');
    await tester.scrollUntilVisible(find.text('Open supporting source block').hitTestable(),-100,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.text('Open supporting source block'));await tester.pumpAndSettle();expect(find.text('Source a block 3'),findsOneWidget);
  });

  testWidgets('Original integrity is opt-in and never labeled authenticity verification',(tester)async{
    final fake=_FakeRepo();await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>fake),consumerDocumentProvider.overrideWith((ref,id)async=>doc())],child:const MaterialApp(home:ConsumerDocumentPage(itemId:'a'))));await tester.pumpAndSettle();
    await tester.tap(find.text('Original integrity (not authenticity)'));await tester.pumpAndSettle();await tester.scrollUntilVisible(find.text('Compare original bytes to recorded hash').hitTestable(),100,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.text('Compare original bytes to recorded hash'));await tester.pumpAndSettle();expect(find.textContaining('A matching hash does not prove authenticity'),findsOneWidget);
  });

  testWidgets('Comparison reports differences without choosing a winner',(tester)async{
    final result=ConsumerComparison(itemIds:['a','b'],explanation:'Selected sources may concern different purchases. No source is silently preferred.',fields:[ConsumerComparisonField(field:'receipt_total',result:'different_extracted_values',claims:[ConsumerClaim.fromJson(claimJson()),ConsumerClaim.fromJson(claimJson(id:'c2',item:'b'))],missingItemIds:[])]);
    await tester.pumpWidget(ProviderScope(overrides:[consumerCompareProvider.overrideWith((ref,ids)async=>result)],child:const MaterialApp(home:ConsumerComparePage(idsJson:'["a","b"]'))));await tester.pumpAndSettle();expect(find.textContaining('No source is silently preferred'),findsOneWidget);expect(find.textContaining('different extracted values'),findsOneWidget);
  });

  testWidgets('No extracted consumer fields does not imply no rights or policies',(tester)async{
    await tester.pumpWidget(ProviderScope(overrides:[consumerDocumentsProvider.overrideWith((ref)async=>[])],child:const MaterialApp(home:ConsumerDocumentsPage())));await tester.pumpAndSettle();expect(find.textContaining('No consumer candidates yet'),findsOneWidget);expect(find.textContaining('not verified transactions'),findsOneWidget);
  });
}
