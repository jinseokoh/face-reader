import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/core/theme.dart';
import 'package:face_reader/app.dart';

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
      title: 'AI 관상',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainApp(),
    );
  }
}
