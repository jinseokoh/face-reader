import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart' hide Gender;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/constants/compat_hashtags.dart';
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
  final GlobalKey _shareCardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.album.alias ?? '궁합'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '카드 이미지 공유',
            onPressed: () => _showShareCardSheet(context),
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
  // Share
  // ─────────────────────────────────────────────────────────────

  // ─── Share card sheet (이미지 1장 공유) ───
  void _showShareCardSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text('한 장 공유 카드',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('인스타·카톡에 그대로 보낼 수 있는 정사각 카드입니다.',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4)),
                const SizedBox(height: 14),
                Center(
                  child: RepaintBoundary(
                    key: _shareCardKey,
                    child: _CompatShareCard(
                      my: widget.my,
                      album: widget.album,
                      report: _bundle.report,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _captureAndShareCard(ctx),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('이미지로 공유',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _captureAndShareCard(BuildContext sheetContext) async {
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('share card not mounted');
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('failed to encode png');
      }
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/face_compat_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      final r = _bundle.report;
      final myAlias = widget.my.alias ?? '나';
      final albumAlias = widget.album.alias ?? '상대';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text:
              '$myAlias × $albumAlias — ${r.label.korean} ${r.total.toStringAsFixed(0)}/100',
        ),
      );
      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    } catch (e, st) {
      debugPrint('[CompatShareCard] capture failed: $e\n$st');
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('공유 카드 생성 실패: $e')),
      );
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
  final double size;
  const _Thumb({required this.path, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final p = path;
    final file = p != null ? File(p) : null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(8),
        image: file != null && file.existsSync()
            ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
            : null,
      ),
      child: file == null || !file.existsSync()
          ? Icon(Icons.person,
              color: AppTheme.textHint, size: (size * 0.5).clamp(20, 32))
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

// ─────────────────────────────────────────────────────────────
// Compat 한 장 공유 카드 (인스타·카톡)
// ─────────────────────────────────────────────────────────────

class _CompatPalette {
  static const darkBrown = Color(0xFF5C4033);
  static const warmBrown = Color(0xFF7B5B3A);
  static const sand = Color(0xFFBFA67A);
}

class _CompatShareCard extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  final CompatibilityReport report;
  const _CompatShareCard({
    required this.my,
    required this.album,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    final myAlias = my.alias ?? '나';
    final albumAlias = album.alias ?? '상대';
    final myDemographic =
        '${my.gender.labelKo} · ${my.ageGroup.labelKo} · ${my.faceShape.korean}';
    final albumDemographic =
        '${album.gender.labelKo} · ${album.ageGroup.labelKo} · ${album.faceShape.korean}';
    final tagline = _TotalHeader._labelTagline(report.label);
    final relation =
        '${report.myElement.primary.korean} × ${report.albumElement.primary.korean}  ·  ${_relationKindKo(report.elementRelation.kind)}';

    return Container(
      width: 360,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_CompatPalette.darkBrown, _CompatPalette.warmBrown],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('당신들의 궁합',
                style: TextStyle(
                    color: _CompatPalette.sand,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 14),
            Text(report.label.korean,
                style: const TextStyle(
                    fontFamily: 'SongMyung',
                    color: Colors.white,
                    fontSize: 26,
                    letterSpacing: 4)),
            const SizedBox(height: 6),
            Text(tagline,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _CompatPalette.sand,
                    fontSize: 12,
                    letterSpacing: 1)),
            const SizedBox(height: 18),
            _CompatChipsBlock(report: report),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _CompatShareSide(
                        report: my,
                        alias: myAlias,
                        demographic: myDemographic)),
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('×',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w300)),
                ),
                Expanded(
                    child: _CompatShareSide(
                        report: album,
                        alias: albumAlias,
                        demographic: albumDemographic)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Text(relation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompatChipsBlock extends StatelessWidget {
  final CompatibilityReport report;
  const _CompatChipsBlock({required this.report});

  @override
  Widget build(BuildContext context) {
    final chips = chipsForCompat(report);
    final split = splitChips(chips);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (split.warm.isNotEmpty) ...[
          _ChipRowLabel(
              text: '장점',
              dotColor: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final c in split.warm) _ShareHashtag(chip: c)],
          ),
        ],
        if (split.warm.isNotEmpty && split.cool.isNotEmpty)
          const SizedBox(height: 12),
        if (split.cool.isNotEmpty) ...[
          _ChipRowLabel(
              text: '단점', dotColor: _CompatPalette.sand),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final c in split.cool) _ShareHashtag(chip: c)],
          ),
        ],
      ],
    );
  }
}

class _ChipRowLabel extends StatelessWidget {
  final String text;
  final Color dotColor;
  const _ChipRowLabel({required this.text, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
              color: dotColor, borderRadius: BorderRadius.circular(3)),
        ),
        Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      ],
    );
  }
}

class _ShareHashtag extends StatelessWidget {
  final CompatChip chip;
  const _ShareHashtag({required this.chip});

  @override
  Widget build(BuildContext context) {
    final isWarm = chip.tone == CompatChipTone.warm;
    final bg = isWarm
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.22);
    final border = isWarm
        ? Colors.white.withValues(alpha: 0.30)
        : Colors.white.withValues(alpha: 0.10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Text(chip.label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2)),
    );
  }
}

class _CompatShareSide extends StatelessWidget {
  final FaceReadingReport report;
  final String alias;
  final String demographic;
  const _CompatShareSide({
    required this.report,
    required this.alias,
    required this.demographic,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Thumb(path: report.thumbnailPath, size: 56),
        const SizedBox(height: 8),
        Text(alias,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(demographic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: _CompatPalette.sand, fontSize: 10.5, height: 1.3)),
      ],
    );
  }
}
