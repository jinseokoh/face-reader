import 'package:face_reader/app.dart';
import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '위험한 관상가',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainApp(),
    );
  }
}
