import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/compat/compat_adapter.dart';
import 'package:face_reader/domain/services/compat/compat_label.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
import 'package:face_reader/domain/services/compat/compat_sub_display.dart';
import 'package:face_reader/domain/services/compat/five_element.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/screens/compatibility/compatibility_detail_screen.dart';

/// 궁합 탭 — 앨범 리스트.
/// 카드 탭 → `CompatibilityDetailScreen` push (현재 화면 그대로).
class CompatibilityScreen extends ConsumerWidget {
  const CompatibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final myFace = history
        .where((r) => r.isMyFace)
        .cast<FaceReadingReport?>()
        .firstOrNull;
    final albums =
        history.where((r) => !r.isMyFace).toList(growable: false);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('궁합'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '궁합 엔진 안내',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: _buildBody(context, myFace, albums),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('궁합 엔진 안내',
            style: TextStyle(
                fontFamily: 'SongMyung',
                fontSize: 18,
                color: AppTheme.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('두 얼굴을 4개 층위로 비교해 100점 만점으로 채점합니다.',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5)),
              SizedBox(height: 14),
              _InfoRow(
                  title: '오행',
                  weight: '20%',
                  body: '얼굴형 기본 성향. 木·火·土·金·水 의 생극 관계.'),
              _InfoRow(
                  title: '궁위',
                  weight: '40%',
                  body: '결혼·가족·재물·자녀 등 12개 영역의 짝.'),
              _InfoRow(
                  title: '기질',
                  weight: '25%',
                  body: '눈·코·입·삼정·음양의 짝. 성격 합.'),
              _InfoRow(
                  title: '친밀',
                  weight: '15%',
                  body: '부부·친밀감 영역. 30~50대 이성 조합에서만 활성.'),
              SizedBox(height: 16),
              Text('등급',
                  style: TextStyle(
                      fontFamily: 'SongMyung',
                      fontSize: 14,
                      color: AppTheme.textPrimary)),
              SizedBox(height: 8),
              _LabelRow(label: CompatLabel.cheonjakjihap),
              _LabelRow(label: CompatLabel.sangkyeongyeobin),
              _LabelRow(label: CompatLabel.mahapgaseong),
              _LabelRow(label: CompatLabel.hyeonggeuknanjo),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    FaceReadingReport? myFace,
    List<FaceReadingReport> albums,
  ) {
    if (myFace == null) {
      return _guide(
        '내 얼굴이 설정되어 있지 않습니다.',
        '히스토리에서 내 얼굴을 선택한 뒤 여기로 돌아오세요.',
      );
    }
    if (albums.isEmpty) {
      return _guide(
        '비교할 앨범 얼굴이 없습니다.',
        '홈에서 한 장 더 캡처한 뒤 궁합을 확인해 보세요.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: albums.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final album = albums[i];
        return _CompatListCard(
          my: myFace,
          album: album,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  CompatibilityDetailScreen(my: myFace, album: album),
            ),
          ),
        );
      },
    );
  }

  Widget _guide(String title, String detail) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.textHint, size: 56),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.5)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Compat list card
// ─────────────────────────────────────────────────────────────

class _CompatListCard extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  final VoidCallback onTap;
  const _CompatListCard({
    required this.my,
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bundle = analyzeCompatibilityFromReports(my: my, album: album);
    final r = bundle.report;
    final labelColor = _labelColor(r.label);
    final alias = album.alias;
    final demographic =
        '${album.gender.labelKo} · ${album.ageGroup.labelKo} · ${album.faceShape.korean}';

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Thumb(path: album.thumbnailPath, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alias ?? demographic,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary)),
                        if (alias != null) ...[
                          const SizedBox(height: 2),
                          Text(demographic,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary)),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: labelColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${r.label.korean} (${r.label.hanja})',
                            style: TextStyle(
                                fontFamily: 'SongMyung',
                                fontSize: 13,
                                color: labelColor,
                                letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(r.total.toStringAsFixed(0),
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w300,
                              color: AppTheme.textPrimary,
                              height: 1)),
                      const SizedBox(height: 2),
                      const Text('/ 100',
                          style: TextStyle(
                              fontSize: 10, color: AppTheme.textHint)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: AppTheme.border),
              const SizedBox(height: 12),
              Text(
                '${r.myElement.primary.korean} × ${r.albumElement.primary.korean}  ·  ${_relationKindKo(r.elementRelation.kind)}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.accent,
                    letterSpacing: 1),
              ),
              const SizedBox(height: 10),
              _MiniBars(report: r),
            ],
          ),
        ),
      ),
    );
  }

  static Color _labelColor(CompatLabel l) {
    switch (l) {
      case CompatLabel.cheonjakjihap:
        return const Color(0xFFE2A857);
      case CompatLabel.sangkyeongyeobin:
        return const Color(0xFF7BAE7E);
      case CompatLabel.mahapgaseong:
        return AppTheme.textSecondary;
      case CompatLabel.hyeonggeuknanjo:
        return const Color(0xFF8E6F70);
    }
  }

  static String _relationKindKo(ElementRelationKind k) {
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
}

class _MiniBars extends StatelessWidget {
  final CompatibilityReport report;
  const _MiniBars({required this.report});

  @override
  Widget build(BuildContext context) {
    final entries = <_MiniEntry>[
      _MiniEntry('오행',
          subScoreToDisplay(CompatSubKind.element, report.sub.elementScore)!,
          false),
      _MiniEntry('궁위',
          subScoreToDisplay(CompatSubKind.palace, report.sub.palaceScore)!,
          false),
      _MiniEntry(
          '기질', subScoreToDisplay(CompatSubKind.qi, report.sub.qiScore)!, false),
      _MiniEntry(
        '친밀',
        subScoreToDisplay(
              CompatSubKind.intimacy,
              report.sub.intimacyScore,
              gateOff: !report.intimacy.gateActive,
            ) ??
            0.0,
        !report.intimacy.gateActive,
      ),
    ];
    return Row(
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          Expanded(child: _MiniBar(entry: entries[i])),
          if (i < entries.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _MiniEntry {
  final String korean;
  final double value;
  final bool muted;
  const _MiniEntry(this.korean, this.value, this.muted);
}

class _MiniBar extends StatelessWidget {
  final _MiniEntry entry;
  const _MiniBar({required this.entry});

  @override
  Widget build(BuildContext context) {
    final frac = (entry.value.clamp(0, 100) / 100.0).toDouble();
    final color = entry.muted ? AppTheme.textHint : AppTheme.accent;
    final labelColor =
        entry.muted ? AppTheme.textHint : AppTheme.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              entry.korean,
              style: TextStyle(
                  fontFamily: 'SongMyung',
                  fontSize: 11,
                  color: labelColor,
                  letterSpacing: 0.5),
            ),
            Text(entry.muted ? '—' : entry.value.toStringAsFixed(0),
                style: TextStyle(
                    fontSize: 11,
                    color: entry.muted
                        ? AppTheme.textHint
                        : AppTheme.textPrimary)),
          ],
        ),
        const SizedBox(height: 4),
        Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            FractionallySizedBox(
              widthFactor: entry.muted ? 0 : frac,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Thumb
// ─────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final String? path;
  final double size;
  const _Thumb({required this.path, this.size = 48});
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
          ? const Icon(Icons.person, color: AppTheme.textHint)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Info dialog rows
// ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String title;
  final String weight;
  final String body;
  const _InfoRow({
    required this.title,
    required this.weight,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'SongMyung',
                      fontSize: 14,
                      color: AppTheme.textPrimary)),
              const SizedBox(width: 8),
              Text(weight,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.accent)),
            ],
          ),
          const SizedBox(height: 2),
          Text(body,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.45)),
        ],
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  final CompatLabel label;
  const _LabelRow({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = _CompatListCard._labelColor(label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              '${label.korean} (${label.hanja}) — ${_tagline(label)}',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  static String _tagline(CompatLabel l) {
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
