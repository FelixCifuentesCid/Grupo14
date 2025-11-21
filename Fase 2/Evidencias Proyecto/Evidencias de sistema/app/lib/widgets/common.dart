import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  final String title; 
  final Widget child; 
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  const AppShell({super.key, required this.title, required this.child, this.actions, this.floatingActionButton});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(child: child),
    floatingActionButton: floatingActionButton,
  );
}

class Busy extends StatelessWidget { const Busy({super.key}); @override
  Widget build(BuildContext c)=> const Center(child: CircularProgressIndicator()); }

SnackBar ok(String m)=> SnackBar(content: Text(m));
SnackBar ko(String m)=> SnackBar(content: Text(m), backgroundColor: Colors.redAccent);

class Gap extends SizedBox { const Gap(double v, {super.key}) : super(height:v, width:v); }
