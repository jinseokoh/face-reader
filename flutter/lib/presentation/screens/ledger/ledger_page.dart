import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/coin_transaction.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/compat_unlock_provider.dart';
import 'package:facely/presentation/providers/wallet_provider.dart';
import 'package:facely/presentation/widgets/login_entry_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

const _txDescriptionLabels = {
  'compat-unlock': '궁합 보기',
};

String _describeTx(CoinTransaction tx) {
  final desc = tx.description;
  if (desc != null) {
    return _txDescriptionLabels[desc] ?? desc;
  }
  return tx.kind.label;
}

Widget _txIconAvatar(CoinTransaction tx) {
  return CircleAvatar(
    radius: 18,
    backgroundColor: Colors.white,
    child: FaIcon(
      switch (tx.kind) {
        CoinTxKind.purchase => FontAwesomeIcons.cartPlus,
        CoinTxKind.bonus => FontAwesomeIcons.gift,
        CoinTxKind.refund => FontAwesomeIcons.arrowRotateLeft,
        CoinTxKind.spend => FontAwesomeIcons.circleMinus,
      },
      color: AppTheme.textSecondary,
      size: 16,
    ),
  );
}

class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final history = ref.watch(walletHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('코인 사용내역'),
        actions: [
          if (user != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.coins,
                      color: AppTheme.textPrimary, size: 15),
                  const SizedBox(width: 6),
                  Text('${user.coins}개', style: AppText.subTitle),
                ],
              ),
            ),
          ],
        ],
      ),
      body: user == null
          ? const _LoggedOutView()
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(authProvider.notifier).refreshCoins();
                ref.invalidate(walletHistoryProvider);
                await ref.read(walletHistoryProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('거래 내역', style: AppText.subTitle),
                  ),
                  const SizedBox(height: 8),
                  history.when(
                    data: (rows) => rows.isEmpty
                        ? const _EmptyHistory()
                        : Column(
                            children: [
                              for (final tx in rows) _TransactionTile(tx: tx),
                            ],
                          ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text('거래 내역을 불러오지 못했습니다\n$e',
                            style: AppText.caption
                                .copyWith(color: AppColors.textHint),
                            textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text('아직 거래 내역이 없습니다',
            style: AppText.caption.copyWith(color: AppColors.textHint)),
      ),
    );
  }
}

class _LoggedOutView extends StatelessWidget {
  const _LoggedOutView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.receipt,
                color: AppTheme.textHint, size: 48),
            const SizedBox(height: 16),
            Text('로그인 후 코인 사용내역을 볼 수 있습니다',
                style: AppText.body.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            const LoginEntryButton(),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  final CoinTransaction tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCredit = tx.kind.isCredit;
    final sign = isCredit ? '+' : '';
    final amountColor =
        isCredit ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    // 결제 시점 partner 스냅샷(unlocks.partner_body) 에서 해석 — 로컬 히스토리
    // 의존 없이 기기·재설치 무관하게 사진·인적정보가 항상 뜬다.
    final snapshots =
        ref.watch(compatPartnerSnapshotsProvider).asData?.value ?? const {};
    final album = _resolveAlbum(snapshots);
    final demographic = album == null
        ? null
        : '${album.gender.labelKo} · ${album.ageGroup.labelKo} · ${album.faceShape.korean}';
    final subtitle = album == null
        ? null
        : (album.alias != null && album.alias!.isNotEmpty
            ? '${album.alias} · $demographic'
            : demographic);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            _TxLeading(tx: tx, album: album),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_describeTx(tx),
                      style: AppText.subTitle
                          .copyWith(fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppText.hint
                            .copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    timeago.format(tx.createdAt, locale: 'ko'),
                    style: AppText.hint,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$sign${tx.amount}',
                    style: AppText.subTitle.copyWith(color: amountColor)),
                Text('잔액 ${tx.balanceAfter}', style: AppText.hint),
              ],
            ),
          ],
        ),
      ),
    );
  }

  FaceReadingReport? _resolveAlbum(Map<String, FaceReadingReport> snapshots) {
    if (tx.description != 'compat-unlock') return null;
    // reference_id 는 곧 pair_key — 스냅샷 맵 직접 조회 (구분자 파싱 불필요).
    final ref = tx.referenceId;
    if (ref == null) return null;
    return snapshots[ref];
  }
}

class _TxLeading extends StatelessWidget {
  final CoinTransaction tx;
  final FaceReadingReport? album;
  const _TxLeading({required this.tx, required this.album});

  @override
  Widget build(BuildContext context) {
    // 결제 시점 partner 스냅샷의 R2 CDN 키로 항상 사진 노출(캐시). 키가 없거나
    // 로드 실패 시에만 거래 아이콘.
    final cdn = ThumbnailPaths.cdnUrl(album?.thumbnailKey);
    if (cdn != null) {
      return _frame(CachedNetworkImage(
        imageUrl: cdn,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            Container(width: 36, height: 36, color: AppTheme.surface),
        errorWidget: (_, _, _) => _txIconAvatar(tx),
      ));
    }
    return _txIconAvatar(tx);
  }

  Widget _frame(Widget child) =>
      ClipRRect(borderRadius: BorderRadius.circular(8), child: child);
}
