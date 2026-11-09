import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/repository.dart';
import 'package:refract/features/import/capture_jobs_page.dart';
class _JobRepo implements RefractRepository {
 final calls=<String>[];
 @override Future<Map<String,dynamic>> capture(String action,Map<String,dynamic> payload) async {calls.add(action);return {'status':action=='cancel'?'cancelled':'completed','result_item_id':'saved'};}
 @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
Map<String,dynamic> _job(String status)=>{'id':'job-test-token-123456','format':'text','status':status,'attempts':1,'created_ts':42,'error':null,'result_item_id':status=='completed'?'saved':null};
void main(){
 testWidgets('Opening interrupted job history does not retry without a user action',(tester)async{
  final repo=_JobRepo();await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>repo),captureJobsProvider.overrideWith((ref)async=>[_job('processing')])],child:const MaterialApp(home:CaptureJobsPage())));await tester.pumpAndSettle();expect(repo.calls,isEmpty);
  await tester.scrollUntilVisible(find.text('Resume if interrupted'),150,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.text('Resume if interrupted'));await tester.pumpAndSettle();expect(repo.calls,['run']);
 });
 testWidgets('Cancel requires confirmation; completed sources have no cancellation button',(tester)async{
  final repo=_JobRepo();await tester.pumpWidget(ProviderScope(overrides:[bootstrapProvider.overrideWith((ref)async=>repo),captureJobsProvider.overrideWith((ref)async=>[_job('failed')])],child:const MaterialApp(home:CaptureJobsPage())));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Cancel pending save'),150,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.text('Cancel pending save'));await tester.pumpAndSettle();expect(repo.calls,isEmpty);await tester.tap(find.text('Keep job'));await tester.pumpAndSettle();expect(repo.calls,isEmpty);
  await tester.tap(find.text('Cancel pending save'));await tester.pumpAndSettle();await tester.tap(find.widgetWithText(FilledButton,'Cancel pending save'));await tester.pumpAndSettle();expect(repo.calls,['cancel']);
  await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
  await tester.pumpWidget(ProviderScope(overrides:[captureJobsProvider.overrideWith((ref)async=>[_job('completed')])],child:const MaterialApp(home:CaptureJobsPage())));await tester.pumpAndSettle();expect(find.text('Run / retry'),findsNothing);expect(find.text('Cancel pending save'),findsNothing);expect(find.text('Open saved source'),findsOneWidget);
 });
}
