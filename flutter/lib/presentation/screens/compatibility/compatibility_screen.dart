import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/compat/compat_adapter.dart';
import 'package:face_reader/domain/services/compat/compat_label.dart';
import 'package:face_reader/domain/services/compat/compat_narrative.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';

/// 궁합 엔진 v1 — 五行·十二宮·五官·三停·陰陽 4-layer hybrid.
/// 설계 SSOT: `docs/compat/FRAMEWORK.md`.
class CompatibilityScreen extends ConsumerStatefulWidget {
  const CompatibilityScreen({super.key});

  @override
  ConsumerState<CompatibilityScreen> createState() =>
      _CompatibilityScreenState();
}

class _CompatibilityScreenState extends ConsumerState<CompatibilityScreen> {
  String? _selectedAlbumId;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final myFace = history.where((r) => r.isMyFace).cast<FaceReadingReport?>().firstOrNull;
    final albums =
        history.where((r) => !r.isMyFace).toList(growable: false);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('궁합')),
      body: _buildBody(myFace, albums),
    );
  }

  Widget _buildBody(FaceReadingReport? myFace, List<FaceReadingReport> albums) {
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

    final selected = _resolveSelected(albums);
    final bundle = selected == null
        ? null
        : analyzeCompatibilityFromReports(my: myFace, album: selected);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        _PersonStrip(my: myFace, album: selected),
        const SizedBox(height: 12),
        _AlbumPicker(
          albums: albums,
          selectedId: _selectedKey(selected),
          onSelect: (r) => setState(() {
            _selectedAlbumId = _selectedKey(r);
          }),
        ),
        const SizedBox(height: 20),
        if (bundle != null) ...[
          _TotalHeader(report: bundle.report),
          const SizedBox(height: 16),
          _SubScorePanel(report: bundle.report),
          const SizedBox(height: 20),
          _NarrativeSections(narrative: bundle.narrative),
        ] else
          _guide('앨범을 선택해 주세요.', '위 chip 에서 비교 대상 얼굴을 고르면 해석이 열립니다.'),
      ],
    );
  }

  String _selectedKey(FaceReadingReport? r) =>
      r?.supabaseId ?? r?.timestamp.toIso8601String() ?? '';

  FaceReadingReport? _resolveSelected(List<FaceReadingReport> albums) {
    if (_selectedAlbumId != null) {
      for (final a in albums) {
        if (_selectedKey(a) == _selectedAlbumId) return a;
      }
    }
    return albums.first;
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
                      color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Components
// ─────────────────────────────────────────────────────────────

class _PersonStrip extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport? album;
  const _PersonStrip({required this.my, required this.album});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _PersonCard(report: my, label: '我')),
        const SizedBox(width: 12),
        const Icon(Icons.compare_arrows, color: AppTheme.textHint),
        const SizedBox(width: 12),
        Expanded(
          child: album == null
              ? _PersonCard.empty()
              : _PersonCard(report: album!, label: '彼'),
        ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  final FaceReadingReport? report;
  final String label;
  const _PersonCard({required FaceReadingReport this.report, required this.label});
  const _PersonCard.empty()
      : report = null,
        label = '';

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _Thumb(path: r?.thumbnailPath),
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
                const SizedBox(height: 2),
                Text(r?.alias ?? (r == null ? '대상 없음' : '이름 없음'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary)),
                if (r != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${r.gender.name} · ${r.ageGroup.name} · ${r.faceShape.name}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
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

class _AlbumPicker extends StatelessWidget {
  final List<FaceReadingReport> albums;
  final String selectedId;
  final ValueChanged<FaceReadingReport> onSelect;
  const _AlbumPicker({
    required this.albums,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final r = albums[i];
          final id = r.supabaseId ?? r.timestamp.toIso8601String();
          final sel = id == selectedId;
          return ChoiceChip(
            label: Text(r.alias ?? '앨범 ${i + 1}'),
            selected: sel,
            onSelected: (_) => onSelect(r),
          );
        },
      ),
    );
  }
}

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
          Text(label.hanja,
              style: const TextStyle(
                  fontFamily: 'SongMyung',
                  fontSize: 26,
                  color: AppTheme.textPrimary,
                  letterSpacing: 4)),
          const SizedBox(height: 4),
          Text(label.korean,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  letterSpacing: 2)),
          const SizedBox(height: 14),
          Text(report.total.toStringAsFixed(0),
              style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w300,
                  color: AppTheme.textPrimary,
                  height: 1)),
          const SizedBox(height: 4),
          const Text('/ 99',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
          const SizedBox(height: 10),
          Text('${report.myElement.primary.hanja}形  '
              '×  ${report.albumElement.primary.hanja}形  '
              '— ${report.elementRelation.kind.hanja}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.accent, letterSpacing: 1.5)),
        ],
      ),
    );
  }
}

class _SubScorePanel extends StatelessWidget {
  final CompatibilityReport report;
  const _SubScorePanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final rows = <_SubRow>[
      _SubRow('五形和', report.sub.elementScore, 0.20),
      _SubRow('宮位調', report.sub.palaceScore, 0.40),
      _SubRow('氣質合', report.sub.qiScore, 0.25),
      _SubRow(
        '情性諧',
        report.sub.intimacyScore,
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
    final frac = (row.value.clamp(0, 99) / 99.0).toDouble();
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
              row.muted ? '— · ${(row.weight * 100).toInt()}%' :
                  '${row.value.toStringAsFixed(0)} · ${(row.weight * 100).toInt()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrativeSections extends StatelessWidget {
  final CompatNarrative narrative;
  const _NarrativeSections({required this.narrative});

  static const _titles = [
    '總評',
    '五形相配',
    '宮位照應',
    '氣質合章',
    '情性之合',
    '長久之道',
  ];

  @override
  Widget build(BuildContext context) {
    final bodies = <String>[
      narrative.overview,
      narrative.elementSection,
      narrative.palaceSection,
      narrative.qiSection,
      if (narrative.intimacySection != null) narrative.intimacySection!,
      narrative.longTermSection,
    ];
    final titleOffsets = narrative.intimacySection == null
        ? const [0, 1, 2, 3, 5]
        : const [0, 1, 2, 3, 4, 5];
    return Column(
      children: [
        for (int i = 0; i < bodies.length; i++)
          _NarrativeCard(title: _titles[titleOffsets[i]], body: bodies[i]),
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
