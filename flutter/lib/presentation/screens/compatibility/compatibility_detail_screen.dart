import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart' hide Gender;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/compat/compat_adapter.dart';
import 'package:face_reader/domain/services/compat/compat_label.dart';
import 'package:face_reader/domain/services/compat/compat_narrative.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
import 'package:face_reader/domain/services/compat/compat_sub_display.dart';
import 'package:face_reader/domain/services/compat/five_element.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';

/// 궁합 상세 — 한 쌍(나 × 앨범) 의 전체 해석.
/// 리스트 카드(`compatibility_screen.dart`) 에서 push 로 진입.
class CompatibilityDetailScreen extends ConsumerStatefulWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  const CompatibilityDetailScreen({
    super.key,
    required this.my,
    required this.album,
  });

  @override
  ConsumerState<CompatibilityDetailScreen> createState() =>
      _CompatibilityDetailScreenState();
}

class _CompatibilityDetailScreenState
    extends ConsumerState<CompatibilityDetailScreen> {
  late final CompatibilityBundle _bundle =
      analyzeCompatibilityFromReports(my: widget.my, album: widget.album);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.album.alias ?? '궁합'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: '저장',
            onPressed: () => _showSaveOptions(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '카카오 공유',
            onPressed: () => _shareViaKakao(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          _PersonStrip(my: widget.my, album: widget.album),
          const SizedBox(height: 20),
          _TotalHeader(report: _bundle.report),
          const SizedBox(height: 16),
          _SubScorePanel(report: _bundle.report),
          const SizedBox(height: 20),
          _NarrativeSections(narrative: _bundle.narrative),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Save / share
  // ─────────────────────────────────────────────────────────────

  Future<void> _showSaveOptions(BuildContext context) async {
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn || !context.mounted) return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.copy, color: AppTheme.textSecondary),
                  title: const Text('클립보드에 복사',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _generateText()));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('클립보드에 복사되었습니다')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf,
                      color: AppTheme.textSecondary),
                  title: const Text('PDF로 저장',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _saveToPdf(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveToPdf(BuildContext context) async {
    try {
      final regularData =
          await rootBundle.load('assets/fonts/NotoSerifKR-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/NotoSerifKR-Bold.ttf');
      final regularTtf = pw.Font.ttf(regularData);
      final boldTtf = pw.Font.ttf(boldData);
      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(base: regularTtf, bold: boldTtf),
      );

      final text = _generateText();
      final lines = text.split('\n');

      pdfDoc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
          build: (pw.Context ctx) {
            return lines.map(_renderPdfLine).toList();
          },
        ),
      );

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          dir = await getApplicationDocumentsDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final pairKey =
          '${widget.my.supabaseId ?? widget.my.timestamp.millisecondsSinceEpoch}-${widget.album.supabaseId ?? widget.album.timestamp.millisecondsSinceEpoch}';
      final filename = 'compat-$pairKey.pdf';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(await pdfDoc.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 저장 완료: $filename')),
        );
      }
    } catch (e) {
      debugPrint('[CompatPDF] error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF 저장 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _shareViaKakao(BuildContext context) async {
    try {
      // 공유 link 는 my report 의 supabase URL 을 사용 — 받는 사람이 내 관상을
      // 함께 볼 수 있게. 미저장 상태면 먼저 supabase 에 push.
      String? uuid = widget.my.supabaseId;
      if (uuid == null) {
        uuid = await SupabaseService().saveMetrics(widget.my);
        widget.my.supabaseId = uuid;
      }
      final link = 'https://face.whatsupkorea.com/report/$uuid';
      final r = _bundle.report;
      final myAlias = widget.my.alias ?? '나';
      final albumAlias = widget.album.alias ?? '상대';
      final desc =
          '$myAlias × $albumAlias — ${r.label.korean} ${r.total.toStringAsFixed(0)}/100';

      final template = FeedTemplate(
        content: Content(
          title: '궁합 분석 결과',
          description: desc,
          imageUrl: Uri.parse(
              'https://jicaenyzunjdlcxcdbfb.supabase.co/storage/v1/object/public/assets/share-thumbnail.png'),
          link: Link(
            webUrl: Uri.parse(link),
            mobileWebUrl: Uri.parse(link),
          ),
        ),
        buttons: [
          Button(
            title: '결과 보기',
            link: Link(
              webUrl: Uri.parse(link),
              mobileWebUrl: Uri.parse(link),
            ),
          ),
        ],
      );

      await ShareClient.instance.shareDefault(template: template);
    } catch (e, st) {
      debugPrint('[CompatKakaoShare] error: $e');
      debugPrint('[CompatKakaoShare] stackTrace: $st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공유 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Plain-text export (PDF/clipboard)
  //
  // Marker convention (관상 리포트와 동일):
  //   `=== 제목 ===` H1, `--- 섹션 ---` H2, 그 외 paragraph.
  // ─────────────────────────────────────────────────────────────

  String _generateText() {
    final r = _bundle.report;
    final n = _bundle.narrative;
    final myAlias = widget.my.alias ?? '나';
    final albumAlias = widget.album.alias ?? '상대';
    final time = DateTime.now();
    final timeStr = '${time.year}.${time.month.toString().padLeft(2, '0')}.'
        '${time.day.toString().padLeft(2, '0')}';

    final buf = StringBuffer();
    buf.writeln('=== 궁합 분석 ===');
    buf.writeln('날짜: $timeStr');
    buf.writeln('$myAlias × $albumAlias');
    buf.writeln(
        '${widget.my.gender.labelKo} ${widget.my.ageGroup.labelKo} · ${widget.album.gender.labelKo} ${widget.album.ageGroup.labelKo}');
    buf.writeln();

    buf.writeln('--- 종합 ---');
    buf.writeln('점수: ${r.total.toStringAsFixed(0)}점 / 100점 만점');
    buf.writeln('등급: ${r.label.korean} (${r.label.hanja})');
    buf.writeln(
        '오행: ${r.myElement.primary.korean} × ${r.albumElement.primary.korean} · ${_relationKindKo(r.elementRelation.kind)}');
    buf.writeln();

    buf.writeln('--- 세부 점수 ---');
    buf.writeln(
        '오행: ${subScoreToDisplay(CompatSubKind.element, r.sub.elementScore)!.toStringAsFixed(0)} (가중 20%)');
    buf.writeln(
        '궁위: ${subScoreToDisplay(CompatSubKind.palace, r.sub.palaceScore)!.toStringAsFixed(0)} (가중 40%)');
    buf.writeln(
        '기질: ${subScoreToDisplay(CompatSubKind.qi, r.sub.qiScore)!.toStringAsFixed(0)} (가중 25%)');
    final itDisplay = subScoreToDisplay(
      CompatSubKind.intimacy,
      r.sub.intimacyScore,
      gateOff: !r.intimacy.gateActive,
    );
    buf.writeln(itDisplay != null
        ? '친밀: ${itDisplay.toStringAsFixed(0)} (가중 15%)'
        : '친밀: 이번 조합에서는 따로 계산하지 않음');
    buf.writeln();

    buf.writeln('--- 한줄 요약 ---');
    buf.writeln(n.summary);
    buf.writeln();
    buf.writeln('--- 핵심 궁합 ---');
    buf.writeln(n.corePoints);
    buf.writeln();
    buf.writeln('--- 갈등 시나리오 ---');
    buf.writeln(n.conflictScenarios);
    buf.writeln();
    buf.writeln('--- 운영 전략 ---');
    buf.writeln(n.strategy);
    buf.writeln();
    buf.writeln('--- 점수와 이유 ---');
    buf.writeln(n.scoreReason);
    if (n.intimacyChapter != null) {
      buf.writeln();
      buf.writeln('--- 성숙한 친밀의 결 ---');
      buf.writeln(n.intimacyChapter);
    }

    return buf.toString();
  }

  static pw.Widget _renderPdfLine(String line) {
    if (line.startsWith('===')) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
        child: pw.Text(
          line.replaceAll('=', '').trim(),
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
      );
    }
    if (line.startsWith('---')) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              line.replaceAll('-', '').trim(),
              style: pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              height: 0.6,
              color: PdfColor.fromInt(0xFF5C4033),
            ),
          ],
        ),
      );
    }
    if (line.trim().isEmpty) {
      return pw.SizedBox(height: 6);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Text(
        line,
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 2.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────

String _relationKindKo(ElementRelationKind k) {
  switch (k) {
    case ElementRelationKind.identity:
      return '같은 결의 공명';
    case ElementRelationKind.generating:
      return '내가 상대를 살리는 상생';
    case ElementRelationKind.generated:
      return '상대가 나를 받쳐 주는 상생';
    case ElementRelationKind.overcoming:
      return '내가 상대를 다스리는 상극';
    case ElementRelationKind.overcome:
      return '상대가 나를 누르는 상극';
  }
}

// ─────────────────────────────────────────────────────────────
// Person strip
// ─────────────────────────────────────────────────────────────

class _PersonStrip extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  const _PersonStrip({required this.my, required this.album});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _PersonCard(report: my, label: '나')),
        const SizedBox(width: 16),
        Expanded(child: _PersonCard(report: album, label: '상대')),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  final FaceReadingReport report;
  final String label;
  const _PersonCard({required this.report, required this.label});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final alias = r.alias;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _Thumb(path: r.thumbnailPath),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontFamily: 'SongMyung',
                        fontSize: 15,
                        color: AppTheme.accent)),
                if (alias != null) ...[
                  const SizedBox(height: 2),
                  Text(alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary)),
                ],
                const SizedBox(height: 2),
                Text(
                  '${r.gender.labelKo} · ${r.ageGroup.labelKo} · ${r.faceShape.korean}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? path;
  const _Thumb({required this.path});
  @override
  Widget build(BuildContext context) {
    final p = path;
    final file = p != null ? File(p) : null;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(8),
        image: file != null && file.existsSync()
            ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
            : null,
      ),
      child: file == null || !file.existsSync()
          ? const Icon(Icons.person, color: AppTheme.textHint)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Total header
// ─────────────────────────────────────────────────────────────

class _TotalHeader extends StatelessWidget {
  final CompatibilityReport report;
  const _TotalHeader({required this.report});
  @override
  Widget build(BuildContext context) {
    final label = report.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Text(label.korean,
              style: const TextStyle(
                  fontFamily: 'SongMyung',
                  fontSize: 26,
                  color: AppTheme.textPrimary,
                  letterSpacing: 4)),
          const SizedBox(height: 6),
          Text(_labelTagline(label),
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  letterSpacing: 1)),
          const SizedBox(height: 14),
          Text(report.total.toStringAsFixed(0),
              style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w300,
                  color: AppTheme.textPrimary,
                  height: 1)),
          const SizedBox(height: 4),
          const Text('/ 100',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
          const SizedBox(height: 10),
          Text(
              '${report.myElement.primary.korean} × ${report.albumElement.primary.korean}  · ${_relationKindKo(report.elementRelation.kind)}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.accent, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  static String _labelTagline(CompatLabel l) {
    switch (l) {
      case CompatLabel.cheonjakjihap:
        return '하늘이 맺어 준 드문 자리';
      case CompatLabel.sangkyeongyeobin:
        return '예를 지키며 오래가는 자리';
      case CompatLabel.mahapgaseong:
        return '다듬으며 이루어 가는 자리';
      case CompatLabel.hyeonggeuknanjo:
        return '서로를 조심히 지켜 줘야 하는 자리';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Sub score panel
// ─────────────────────────────────────────────────────────────

class _SubScorePanel extends StatelessWidget {
  final CompatibilityReport report;
  const _SubScorePanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final rows = <_SubRow>[
      _SubRow('오행',
          subScoreToDisplay(CompatSubKind.element, report.sub.elementScore)!,
          0.20),
      _SubRow('궁위',
          subScoreToDisplay(CompatSubKind.palace, report.sub.palaceScore)!,
          0.40),
      _SubRow(
          '기질', subScoreToDisplay(CompatSubKind.qi, report.sub.qiScore)!, 0.25),
      _SubRow(
        '친밀',
        subScoreToDisplay(
              CompatSubKind.intimacy,
              report.sub.intimacyScore,
              gateOff: !report.intimacy.gateActive,
            ) ??
            0.0,
        0.15,
        muted: !report.intimacy.gateActive,
      ),
    ];
    return Column(
      children: [for (final r in rows) _SubBar(row: r)],
    );
  }
}

class _SubRow {
  final String label;
  final double value;
  final double weight;
  final bool muted;
  _SubRow(this.label, this.value, this.weight, {this.muted = false});
}

class _SubBar extends StatelessWidget {
  final _SubRow row;
  const _SubBar({required this.row});
  @override
  Widget build(BuildContext context) {
    final frac = (row.value.clamp(0, 100) / 100.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(row.label,
                style: TextStyle(
                    fontFamily: 'SongMyung',
                    fontSize: 13,
                    color: row.muted
                        ? AppTheme.textHint
                        : AppTheme.textPrimary)),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: row.muted ? AppTheme.textHint : AppTheme.accent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              row.muted
                  ? '— · ${(row.weight * 100).toInt()}%'
                  : '${row.value.toStringAsFixed(0)} · ${(row.weight * 100).toInt()}%',
              textAlign: TextAlign.right,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Narrative sections
// ─────────────────────────────────────────────────────────────

class _NarrativeSections extends StatelessWidget {
  final CompatNarrative narrative;
  const _NarrativeSections({required this.narrative});

  static const _titles = [
    '한줄 요약',
    '핵심 궁합 3가지',
    '현실 갈등 시나리오',
    '관계 운영 전략',
    '궁합 점수와 이유',
  ];

  @override
  Widget build(BuildContext context) {
    final bodies = <String>[
      narrative.summary,
      narrative.corePoints,
      narrative.conflictScenarios,
      narrative.strategy,
      narrative.scoreReason,
    ];
    return Column(
      children: [
        for (int i = 0; i < bodies.length; i++)
          _NarrativeCard(title: _titles[i], body: bodies[i]),
        // 성숙한 연령 이성 페어 전용 optional 섹션 — intimacy.gateActive 통과 시만 렌더.
        if (narrative.intimacyChapter != null)
          _NarrativeCard(
            title: '성숙한 친밀의 결',
            body: narrative.intimacyChapter!,
          ),
      ],
    );
  }
}

class _NarrativeCard extends StatelessWidget {
  final String title;
  final String body;
  const _NarrativeCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'SongMyung',
                  fontSize: 16,
                  color: AppTheme.textPrimary,
                  letterSpacing: 3)),
          const SizedBox(height: 10),
          Text(body,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textPrimary, height: 1.7)),
        ],
      ),
    );
  }
}
