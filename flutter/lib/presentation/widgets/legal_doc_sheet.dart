import 'package:facely/core/theme.dart';
import 'package:facely/data/services/legal_doc_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 이용약관/개인정보처리방침 bottom sheet — facely.kr 의 md 를 fetch 해 렌더.
class LegalDocSheet extends ConsumerWidget {
  const LegalDocSheet._({required this.title, required this.fetcher});

  final String title;
  final Future<String> Function() fetcher;

  static Future<void> showTerms(BuildContext context, WidgetRef ref) {
    final service = ref.read(legalDocServiceProvider);
    return _show(context, title: '이용약관', fetcher: service.fetchTerms);
  }

  static Future<void> showPrivacy(BuildContext context, WidgetRef ref) {
    final service = ref.read(legalDocServiceProvider);
    return _show(context, title: '개인정보처리방침', fetcher: service.fetchPrivacy);
  }

  static Future<void> _show(
    BuildContext context, {
    required String title,
    required Future<String> Function() fetcher,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LegalDocSheet._(title: title, fetcher: fetcher),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // grab handle
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: AppText.modalTitle),
                ),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close, size: 22),
                  color: AppTheme.textHint,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(color: AppTheme.border, height: 1),
          // body
          Expanded(child: _DocBody(fetcher: fetcher)),
        ],
      ),
    );
  }
}

class _DocBody extends StatefulWidget {
  const _DocBody({required this.fetcher});

  final Future<String> Function() fetcher;

  @override
  State<_DocBody> createState() => _DocBodyState();
}

class _DocBodyState extends State<_DocBody> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetcher();
  }

  void _retry() {
    setState(() => _future = widget.fetcher());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '문서를 불러오지 못했습니다.\n인터넷 연결을 확인해 주세요.',
                    textAlign: TextAlign.center,
                    style: AppText.body,
                  ),
                  const SizedBox(height: 16),
                  TextButton(onPressed: _retry, child: const Text('다시 시도')),
                ],
              ),
            ),
          );
        }
        return Markdown(
          data: snap.data!,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            h1: AppText.modalTitle.copyWith(fontSize: 22, height: 1.3),
            h2: AppText.sectionTitle.copyWith(fontSize: 17, height: 1.35),
            h3: AppText.sectionTitle.copyWith(fontSize: 15, height: 1.35),
            p: AppText.body.copyWith(height: 1.7, fontSize: 14),
            listBullet: AppText.body.copyWith(fontSize: 14),
            tableHead: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tableBody: AppText.body.copyWith(fontSize: 13),
            tableBorder: TableBorder.all(color: AppTheme.border, width: 0.8),
            tableCellsPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            blockSpacing: 12,
            h1Padding: const EdgeInsets.only(bottom: 8),
            h2Padding: const EdgeInsets.only(top: 16, bottom: 6),
            h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
          ),
          onTapLink: (_, href, _) {
            // 내부 link 는 sheet 안에서 안 열고 무시 (privacy md 의 /contact 등은
            // app 안에서 의미 없음). 외부 link 가 추후 추가되면 url_launcher 로.
          },
        );
      },
    );
  }
}
