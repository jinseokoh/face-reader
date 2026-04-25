import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/services/analytics_service.dart';
import 'package:face_reader/data/services/compat_unlock_service.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/compat/compat_adapter.dart';
import 'package:face_reader/domain/services/compat/compat_label.dart';
import 'package:face_reader/domain/services/compat/compat_pair_key.dart';
import 'package:face_reader/domain/services/compat/compat_pipeline.dart';
import 'package:face_reader/domain/services/compat/compat_sub_display.dart';
import 'package:face_reader/domain/services/compat/five_element.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/providers/compat_unlock_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/screens/compatibility/compatibility_detail_screen.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
import 'package:face_reader/presentation/widgets/purchase_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 궁합 탭 — 내 얼굴이 아닌 다른 인물 리스트. 기본 lock, 1 코인 해제.
class CompatibilityScreen extends ConsumerWidget {
  const CompatibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final myFace = history
        .where((r) => r.isMyFace)
        .cast<FaceReadingReport?>()
        .firstOrNull;
    final others =
        history.where((r) => !r.isMyFace).toList(growable: false);
    final unlocksAsync = ref.watch(compatUnlocksProvider);
    final unlocked = unlocksAsync.asData?.value ?? const <String>{};

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('궁합'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '궁합 분석에 대하여',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: _body(context, ref, myFace, others, unlocked),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    FaceReadingReport? myFace,
    List<FaceReadingReport> others,
    Set<String> unlocked,
  ) {
    if (myFace == null) {
      return _guide(
        '내 얼굴이 설정되어 있지 않습니다.',
        '관상 (카메라) 탭에서 내 얼굴을 선택한 뒤 여기로 돌아오세요.',
      );
    }
    if (others.isEmpty) {
      return _guide(
        '궁합을 볼 수 있는 다른 사람이 없습니다.',
        '카메라나 앨범으로 다른 사람의 얼굴을 추가하세요.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: others.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final other = others[i];
        final key = tryPairKey(myFace, other);
        final isUnlocked = key != null && unlocked.contains(key);

        if (isUnlocked) {
          return _CompatListCard(
            my: myFace,
            album: other,
            onTap: () {
              AnalyticsService.instance.logClickCompat();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CompatibilityDetailScreen(my: myFace, album: other),
                ),
              );
            },
          );
        }
        return _CompatLockedCard(
          album: other,
          onUnlockPressed: () =>
              _handleUnlockPressed(context, ref, myFace, other),
        );
      },
    );
  }

  /// report.supabaseId 가 null 이면 saveMetrics 로 UUID 를 할당하고 Hive 에
  /// 써서 다음 실행에서도 같은 key 가 유지되도록 한다.
  Future<void> _ensureSupabaseId(
      WidgetRef ref, FaceReadingReport report) async {
    if (report.supabaseId != null) return;
    final uuid = await SupabaseService().saveMetrics(report);
    report.supabaseId = uuid;
    await ref.read(historyProvider.notifier).updateHive();
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

  Future<void> _handleUnlockPressed(
    BuildContext context,
    WidgetRef ref,
    FaceReadingReport my,
    FaceReadingReport album,
  ) async {
    AnalyticsService.instance.logClickCompat();
    // 1. 로그인 확인.
    final auth = ref.read(authProvider.notifier);
    if (!auth.isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (!ok || !context.mounted) return;
    }

    // 2. supabaseId 보장 — 없으면 saveMetrics 로 생성 후 Hive 갱신.
    try {
      await _ensureSupabaseId(ref, my);
      await _ensureSupabaseId(ref, album);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 중 오류: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }

    final key = tryPairKey(my, album);
    if (key == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장된 ID 를 찾을 수 없습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
      return;
    }

    // 3. 잔액 확인.
    final balance = auth.coins;
    if (balance < 1) {
      if (!context.mounted) return;
      await PurchaseSheet.show(context, onPurchased: () async {
        if (!context.mounted) return;
        // 충전 성공 시 다시 시도.
        await _handleUnlockPressed(context, ref, my, album);
      });
      return;
    }

    // 4. 확인 다이얼로그.
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('궁합 해제',
            style: TextStyle(
                fontFamily: 'SongMyung',
                fontSize: 17,
                color: AppTheme.textPrimary)),
        content: Text(
          '1 코인을 사용해 이 궁합을 해제할까요?\n잔액 $balance → ${balance - 1}',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // 5. RPC.
    final int newBalance;
    try {
      newBalance = await CompatUnlockService().unlock(key);
    } catch (e, st) {
      debugPrint('[CompatUnlock] unlock failed: $e\n$st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('해제 중 오류: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (newBalance == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('코인이 부족합니다.')),
      );
      return;
    }

    // 6. 갱신.
    await auth.refreshCoins();
    ref.invalidate(compatUnlocksProvider);
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('궁합 분석에 대하여',
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
            child: const Text('닫기',
                style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Unlocked card — 기존 구조 그대로.
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

// ─────────────────────────────────────────────────────────────
// Locked card — 기본 상태. 상대 프로필만 보여주고 해제 CTA.
// ─────────────────────────────────────────────────────────────

class _CompatLockedCard extends ConsumerWidget {
  final FaceReadingReport album;
  final VoidCallback onUnlockPressed;
  const _CompatLockedCard({
    required this.album,
    required this.onUnlockPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(authProvider) != null;
    final coins = ref.watch(authProvider)?.coins ?? 0;
    final alias = album.alias;
    final demographic =
        '${album.gender.labelKo} · ${album.ageGroup.labelKo} · ${album.faceShape.korean}';

    final cta = isLoggedIn
        ? '1 코인으로 해제 · 잔액 $coins'
        : '카카오 로그인하고 3 코인 받기';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
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
                              fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.lock_outline,
                  color: AppTheme.textHint, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppTheme.border),
          const SizedBox(height: 12),
          Text(
            isLoggedIn
                ? '궁합 결과는 1 코인으로 열어볼 수 있습니다.'
                : '카카오 로그인하면 가입 보너스 3 코인으로 바로 열어볼 수 있어요.',
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: onUnlockPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(cta,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Info dialog helpers
// ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String title;
  final String weight;
  final String body;
  const _InfoRow(
      {required this.title, required this.weight, required this.body});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(title,
                style: const TextStyle(
                    fontFamily: 'SongMyung',
                    fontSize: 13,
                    color: AppTheme.textPrimary)),
          ),
          SizedBox(
            width: 44,
            child: Text(weight,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(body,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
          ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontFamily: 'SongMyung',
                        fontSize: 14,
                        color: AppTheme.textPrimary),
                    children: [
                      TextSpan(text: label.korean),
                      const TextSpan(text: '  '),
                      TextSpan(
                        text: label.hanja,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textHint,
                            fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(_tagline(label),
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _tagline(CompatLabel l) {
    switch (l) {
      case CompatLabel.cheonjakjihap:
        return '얼굴로 읽으면 흔치 않게 잘 맞는 자리 · 좋은 점 압도';
      case CompatLabel.sangkyeongyeobin:
        return '예를 지키며 오래 가는 자리 · 좋은 점 우세';
      case CompatLabel.mahapgaseong:
        return '다듬으며 이루어 가는 자리 · 좋은 점·우려되는 점 균형';
      case CompatLabel.hyeonggeuknanjo:
        return '서로 조심히 지켜 줘야 하는 자리 · 우려되는 점 우세';
    }
  }
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

// ─────────────────────────────────────────────────────────────
// Thumb
// ─────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final String? path;
  final double size;
  const _Thumb({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;
    if (path == null || path!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.border,
        child: const Icon(Icons.person, color: AppTheme.textHint, size: 28),
      );
    }
    final file = File(path!);
    return ClipOval(
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CircleAvatar(
          radius: radius,
          backgroundColor: AppTheme.border,
          child: const Icon(Icons.broken_image,
              color: AppTheme.textHint, size: 20),
        ),
      ),
    );
  }
}
