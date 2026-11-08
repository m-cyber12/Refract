import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/integration_models.dart';
import '../../core/repository.dart';
import 'integration_widgets.dart';

class IntegrationsPage extends ConsumerWidget{
 const IntegrationsPage({super.key});
 @override Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('Optional integrations')),body:ref.watch(integrationCatalogProvider).when(loading:integrationLoading,error:(e,_)=>integrationError(e),data:(rows)=>ListView(padding:const EdgeInsets.all(16),children:[
 const Text('The core works without integrations. Local adapter consent is not OAuth, OS permission or an account connection. No mailbox polling, notification monitoring or calendar account access runs here.'),
 ...rows.map((c)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(c.name,style:Theme.of(context).textTheme.titleLarge),Text(c.available?'Available local adapter · ${c.enabled?'enabled':'disabled'}':'Research only — no connection'),Text(c.scope),Text(c.limitations),if(c.available)...[_PolicyEditor(key:ValueKey('${c.id}:${c.revision}'),capability:c),if(c.enabled)TextButton(onPressed:()=>context.push(c.id=='selected_email'?'/integrations/email':'/integrations/calendar'),child:Text(c.id=='selected_email'?'Review a selected email copy':'Choose confirmed dates for export'))]])))),
 const Text('Additional sources use existing manual capture/share/import. No unrestricted filesystem scan, password collection, hidden source fetch or credential storage is added. Advanced provenance technologies remain research, not verified badges.'),
 ])));
}
class _PolicyEditor extends ConsumerStatefulWidget{
 const _PolicyEditor({super.key,required this.capability});final IntegrationCapability capability;
 @override ConsumerState<_PolicyEditor> createState()=>_PolicyEditorState();
}
class _PolicyEditorState extends ConsumerState<_PolicyEditor>{
 late bool _enabled=widget.capability.enabled;late final Set<String> _categories=widget.capability.allowedCategories.toSet();bool _busy=false;
 Future<void> _apply()async{
  final text=_enabled?'Allow only these user-selected local categories: ${_categories.join(', ')}. Each file/copy still requires explicit selection and review. No account is connected.':'Stop future adapter operations, clear allowed categories and invalidate old previews. Existing library copies and saved calendar files remain; disabling cannot erase external copies.';
  if(!await integrationConfirm(context,_enabled?'Allow selected local categories?':'Disable local adapter?',text)){return;}if(!mounted){return;}setState(()=>_busy=true);
  try{final repo=await ref.read(bootstrapProvider.future);repo.integrations('policy',{'connector_id':widget.capability.id,'enabled':_enabled,'categories':_categories.toList()});integrationRefresh(ref);}catch(e){if(mounted){integrationSnack(context,'$e');}}finally{if(mounted){setState(()=>_busy=false);}}
 }
 @override Widget build(BuildContext context)=>Column(children:[SwitchListTile(value:_enabled,onChanged:_busy?null:(v)=>setState(()=>_enabled=v),title:const Text('Allow this local adapter (no account connection)')),...widget.capability.categories.map((c)=>CheckboxListTile(value:_categories.contains(c),title:Text(c.replaceAll('_',' ')),onChanged:_busy?null:(v)=>setState((){if(v??false){_categories.add(c);}else{_categories.remove(c);}}))),FilledButton(onPressed:_busy||(_enabled&&_categories.isEmpty)?null:_apply,child:const Text('Apply local consent'))]);
}
