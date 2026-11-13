import 'package:flutter/material.dart';
import 'decision_page.dart';
import 'knowledge_map.dart';
import 'compression_page.dart';

class KnowledgePage extends StatelessWidget{
 const KnowledgePage({super.key,this.projectId});final String? projectId;
 @override Widget build(BuildContext context)=>DefaultTabController(length:3,child:Scaffold(appBar:AppBar(title:const Text('Knowledge Hub'),bottom:const TabBar(isScrollable:true,tabs:[Tab(text:'Decisions'),Tab(text:'Knowledge Map'),Tab(text:'Compression')])),body:TabBarView(children:[DecisionsPanel(projectId:projectId),KnowledgeMapPanel(kind:projectId==null?'library':'project',id:projectId??''),CompressionsPanel(projectId:projectId)])));
}
