import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/repository.dart';

Widget integrationLoading()=>const Center(child:CircularProgressIndicator());
Widget integrationError(Object e)=>Padding(padding:const EdgeInsets.all(16),child:SelectableText('$e'));
void integrationRefresh(WidgetRef ref){ref.invalidate(integrationCatalogProvider);ref.invalidate(integrationCalendarProvider);}
void integrationSnack(BuildContext context,String text){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
Future<bool> integrationConfirm(BuildContext context,String title,String text)async=>await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:Text(text),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]))??false;
Future<String?> pickSelectedEmail()async{
 final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['eml'],allowMultiple:false,withData:false,withReadStream:true);if(result==null){return null;}final file=result.files.single;if(file.size>262144){throw const FormatException('Email exceeds 256 KiB. Select/copy the wanted plain text instead.');}
 final builder=BytesBuilder(copy:false);if(file.readStream!=null){await for(final chunk in file.readStream!){if(builder.length+chunk.length>262144){throw const FormatException('Email exceeds 256 KiB.');}builder.add(chunk);}}else if(file.bytes!=null){if(file.bytes!.length>262144){throw const FormatException('Email exceeds 256 KiB.');}builder.add(file.bytes!);}else{throw const FormatException('This provider did not supply a readable file stream. Paste a selected plain-text email instead.');}
 return utf8.decode(builder.takeBytes());
}
Future<bool> saveReviewedCalendar(String ics)async=>await FilePicker.platform.saveFile(dialogTitle:'Save reviewed calendar file (not encrypted)',fileName:'refract-reviewed-dates.ics',type:FileType.custom,allowedExtensions:['ics'],bytes:Uint8List.fromList(utf8.encode(ics)))!=null;
