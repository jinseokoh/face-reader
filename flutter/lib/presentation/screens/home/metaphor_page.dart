import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:face_reader/core/theme.dart';

class MetaphorPage extends StatelessWidget {
  final String markdownText;

  const MetaphorPage({super.key, required this.markdownText});

  static Future<void> show(BuildContext context, String markdownText) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MetaphorPage(markdownText: markdownText),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories,
                        color: AppTheme.textSecondary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      '관상 해석',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: AppTheme.textHint),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(color: AppTheme.border, height: 1),
              Expanded(
                child: Markdown(
                  controller: scrollController,
                  data: markdownText,
                  padding: const EdgeInsets.all(20),
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                        height: 1.7),
                    h1: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                    h2: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    h3: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600),
                    strong: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold),
                    em: TextStyle(
                        color: AppTheme.textSecondary,
                        fontStyle: FontStyle.italic),
                    listBullet: TextStyle(color: AppTheme.textSecondary),
                    blockquoteDecoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border(
                        left:
                            BorderSide(color: AppTheme.textHint, width: 3),
                      ),
                    ),
                    blockquote: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        height: 1.6),
                    horizontalRuleDecoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppTheme.border),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
