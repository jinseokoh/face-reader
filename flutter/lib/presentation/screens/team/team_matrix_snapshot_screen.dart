import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/screens/team/team_matrix_screen.dart';

/// 마감 그룹 결과표의 **최후 fallback** — 서버 `teams.matrix_payload` 스냅샷
/// 렌더 (웹 /g 쇼케이스와 동일 소스). 탈퇴·삭제로 live 계산 가능 멤버가
/// 2명 미만일 때만 진입한다. 점수·페어 상세(unlock)는 스냅샷에 없어 비활성 —
/// 이름 + 밴드 그리드 + 베스트/버금 요약만.
class TeamMatrixSnapshotScreen extends StatelessWidget {
  final String title;
  final Map<String, dynamic> payload;

  const TeamMatrixSnapshotScreen({
    super.key,
    required this.title,
    required this.payload,
  });

  List<String> get _members =>
      [for (final m in (payload['members'] as List? ?? const [])) '$m'];

  List<Map<String, dynamic>> get _pairs => [
        for (final p in (payload['pairs'] as List? ?? const []))
          (p as Map).cast<String, dynamic>(),
      ];

  List<({int a, int b})> _highlight(String key) => [
        for (final p in (payload[key] as List? ?? const []))
          (a: (p as Map)['a'] as int, b: p['b'] as int),
      ];

  Map<String, dynamic>? _pairOf(int i, int j) {
    final a = i < j ? i : j;
    final b = i < j ? j : i;
    for (final p in _pairs) {
      if (p['a'] == a && p['b'] == b) return p;
    }
    return null;
  }

  static Color _hexColor(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length != 7) {
      return AppColors.textHint;
    }
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    final best = _highlight('best');
    final surprises = _highlight('surprises');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 스냅샷 안내 — live 계산 불가 사유를 사실대로.
              Text(
                '탈퇴 등으로 일부 멤버의 관상 정보가 없어,\n결과표가 만들어진 당시 기록을 보여드립니다.',
                style: AppText.caption.copyWith(color: AppColors.textHint),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (best.isNotEmpty)
                TeamSummaryCard(
                  eyebrow: '🥳 베스트 케미',
                  headline: _highlightNames(best, members),
                  caption: '얼굴 관상으로 분석한 두사람의 호흡이 '
                      '현재 조직내에서 최고 수준입니다.',
                ),
              if (surprises.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                TeamSummaryCard(
                  eyebrow: '😲 버금가는 케미',
                  headline: _highlightNames(surprises, members),
                  caption: '얼굴 관상으로 분석한 두사람의 호흡이 '
                      '현재 조직내에서 두번째 최고 수준입니다.',
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                '상호 궁합도 맵',
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildGrid(members),
              const SizedBox(height: AppSpacing.lg),
              _buildLegend(),
            ],
          ),
        ),
      ),
    );
  }

  /// 하이라이트 페어들의 이름 헤드라인 — live 화면의 페어 헤드라인과 같은
  /// 위계(body w700)로, 아바타 없이 이름만.
  Widget _highlightNames(List<({int a, int b})> pairs, List<String> members) {
    String nameOf(int i) => i >= 0 && i < members.length ? members[i] : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < pairs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Text(
            '${nameOf(pairs[i].a)} × ${nameOf(pairs[i].b)}',
            style: AppText.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGrid(List<String> members) {
    const nameWidth = 72.0;
    const cellSize = 44.0;
    final n = members.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 행 — 열 아바타 (스냅샷은 썸네일이 없어 사람 아이콘).
          Row(
            children: [
              const SizedBox(width: nameWidth, height: cellSize),
              for (int j = 0; j < n; j++)
                SizedBox(
                  width: cellSize,
                  height: cellSize,
                  child: Center(child: _iconAvatar(28)),
                ),
            ],
          ),
          for (int i = 0; i < n; i++)
            Row(
              children: [
                SizedBox(
                  width: nameWidth,
                  height: cellSize,
                  child: Row(
                    children: [
                      _iconAvatar(28),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          members[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (int j = 0; j < n; j++) _cell(i, j),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int i, int j) {
    const cellSize = 44.0;
    if (i == j) {
      return SizedBox(
        width: cellSize,
        height: cellSize,
        child: Center(
          child: Text('·',
              style: AppText.caption.copyWith(color: AppColors.textHint)),
        ),
      );
    }
    final pair = _pairOf(i, j);
    if (pair == null) {
      return const SizedBox(width: cellSize, height: cellSize);
    }
    return Container(
      width: cellSize,
      height: cellSize,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.surface, width: 0.5),
      ),
      // live 그리드와 동일 시각 언어 — 밴드 색깔 닷만 (점수 비노출).
      child: Center(
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hexColor(pair['c'] as String?),
          ),
        ),
      ),
    );
  }

  /// 밴드 범례 — 스냅샷 payload 안의 (라벨, 색) 조합에서 유도.
  Widget _buildLegend() {
    final seen = <String>{};
    final entries = <({String label, Color color})>[];
    for (final p in _pairs) {
      final label = p['l'] as String?;
      if (label == null || !seen.add(label)) continue;
      entries.add((label: label, color: _hexColor(p['c'] as String?)));
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        for (final e in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: e.color,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                e.label,
                style: AppText.caption.copyWith(color: AppColors.textHint),
              ),
            ],
          ),
      ],
    );
  }

  Widget _iconAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.border,
      ),
      child: Center(
        child: FaIcon(FontAwesomeIcons.user,
            size: size * 0.45, color: AppColors.textHint),
      ),
    );
  }
}
