import 'package:flutter/material.dart';

import 'package:face_reader/core/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.info_outline, color: AppTheme.textSecondary),
            title: Text('버전',
                style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('1.0.0',
                style: TextStyle(color: AppTheme.textHint)),
          ),
        ],
      ),
    );
  }
}
