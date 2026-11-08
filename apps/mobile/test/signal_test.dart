import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refract/core/models.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/signal/signal_page.dart';

Map<String,dynamic> configJson() => {'enabled':true,'context_enabled':true,'frequency':'daily','lookback_days':7,'upcoming_days':30,'max_per_section':3,'show_unconfirmed':true,'sections':signalSections.keys.toList()};
Map<String,dynamic> eventJson() => {'id':'event1','item_id':'a','block_idx':3,'title':'Renewal candidate','event_ts':1893456000,'category':'renewal','confidence':0.6,'evidence':'Renewal on 2030-01-01.','extracted_ts':100,'status':'unconfirmed'};
SignalEdition edition({bool quiet=false}) => SignalEdition.fromJson({'generated_ts':100,'next_refresh_ts':86500,'enabled':true,'entries':[],'events':quiet?[]:[eventJson()],'quiet':quiet,'message':quiet?'A quiet edition. Nothing meaningful to surface.':'Optional observations, no action required.','limitations':['No external calendar integration.']});

class _FakeRepo implements RefractRepository {
  SignalConfig config=SignalConfig.fromJson(configJson());
  String? reviewed;
  @override SignalConfig signalConfig()=>config;
  @override void configureSignal(SignalConfig value){config=value;}
  @override void reviewSignalEvent(String id,String status){reviewed='$id:$status';}
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}

void main(){
  test('Signal JSON keeps evidence, uncertainty and configurable sections',(){
    final config=SignalConfig.fromJson(configJson());expect(config.changed('frequency','manual').frequency,'manual');expect(config.toJson()['context_enabled'],true);
    final e=edition();expect(e.events.single.status,'unconfirmed');expect(e.events.single.blockIdx,3);expect(e.events.single.evidence,'Renewal on 2030-01-01.');
    final entry=SignalEntry.fromJson({'key':'reading:a','section':'reading','title':'A','explanation':'Saved explicitly','item_ids':['a'],'project_id':null,'block_idx':3,'ts':100,'status':'user_recorded'});
    expect(entry.blockIdx,3);expect(entry.status,'user_recorded');
  });

  testWidgets('A quiet day contains no manufactured event or observation cards',(tester)async{
    await tester.pumpWidget(ProviderScope(overrides:[dailySignalProvider.overrideWith((ref)async=>edition(quiet:true))],child:const MaterialApp(home:DailySignalPage())));
    await tester.pumpAndSettle();expect(find.textContaining('A quiet edition'),findsOneWidget);expect(find.byType(SignalEventCard),findsNothing);expect(find.byType(SignalEntryCard),findsNothing);
  });

  testWidgets('Date candidates require explicit review and link to the exact source block',(tester)async{
    final fake=_FakeRepo();
    final router=GoRouter(routes:[GoRoute(path:'/',builder:(_,state)=>const DailySignalPage()),GoRoute(path:'/reader/:id',builder:(_,state)=>Scaffold(body:Text('Source ${state.pathParameters['id']} block ${state.uri.queryParameters['block']}')))]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>fake),dailySignalProvider.overrideWith((ref)async=>edition())],child:MaterialApp.router(routerConfig:router)));
    await tester.pumpAndSettle();expect(find.textContaining('UNCONFIRMED DATE CANDIDATE'),findsOneWidget);expect(fake.reviewed,isNull);
    await tester.scrollUntilVisible(find.text('Confirm date').hitTestable(),100,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.text('Confirm date'));await tester.pumpAndSettle();expect(fake.reviewed,'event1:confirmed');
    await tester.scrollUntilVisible(find.text('Open date evidence').hitTestable(),-100,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.text('Open date evidence'));await tester.pumpAndSettle();expect(find.text('Source a block 3'),findsOneWidget);
  });

  testWidgets('Context is collapsed and does not retrieve evidence until requested',(tester)async{
    var requests=0;
    await tester.pumpWidget(ProviderScope(overrides:[signalConfigProvider.overrideWith((ref)async=>SignalConfig.fromJson(configJson())),signalContextProvider.overrideWith((ref,request)async{requests++;return SignalContext(enabled:true,entries:[],events:[],message:'Stored context only.');})],child:const MaterialApp(home:Scaffold(body:SingleChildScrollView(child:SignalContextPanel(itemId:'a'))))));
    await tester.pumpAndSettle();expect(requests,0);await tester.tap(find.text('REFRACT CONTEXT · optional'));await tester.pumpAndSettle();expect(requests,1);expect(find.textContaining('No stored context found'),findsOneWidget);
  });

  testWidgets('Frequency controls persist without enabling notifications',(tester)async{
    final fake=_FakeRepo();await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>fake)],child:const MaterialApp(home:SignalSettingsPage())));await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));await tester.pumpAndSettle();await tester.tap(find.text('Manual only').last);await tester.pumpAndSettle();expect(fake.config.frequency,'manual');
    expect(find.textContaining('No push notifications'),findsOneWidget);
  });
}
