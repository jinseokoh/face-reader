import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:face_reader/core/theme.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_reader/domain/models/coin_transaction.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/providers/wallet_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
import 'package:face_reader/presentation/widgets/purchase_sheet.dart';

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

class WalletPage extends ConsumerWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final history = ref.watch(walletHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('지갑')),
      body: user == null
          ? _LoggedOutView(onLogin: () => showLoginBottomSheet(context, ref))
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
                  _BalanceCard(
                    coins: user.coins,
                    onCharge: () => PurchaseSheet.show(
                      context,
                      onPurchased: () => ref.invalidate(walletHistoryProvider),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('거래 내역',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
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
                            style: TextStyle(
                                color: AppTheme.textHint, fontSize: 13),
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

class _BalanceCard extends StatelessWidget {
  final int coins;
  final VoidCallback onCharge;
  const _BalanceCard({required this.coins, required this.onCharge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('보유 코인',
              style: TextStyle(color: AppTheme.textHint, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.toll_outlined,
                  color: AppTheme.textSecondary, size: 28),
              const SizedBox(width: 8),
              Text('$coins',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      height: 1.0)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('개',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onCharge,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('충전하기',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  final CoinTransaction tx;
  const _TransactionTile({required this.tx});

  FaceReadingReport? _resolveAlbum(List<FaceReadingReport> history) {
    if (tx.description != 'compat-unlock') return null;
    final ref = tx.referenceId;
    if (ref == null) return null;
    final parts = ref.split('::');
    if (parts.length != 2) return null;
    final albumId = parts[1];
    if (albumId.isEmpty) return null;
    for (final r in history) {
      if (r.supabaseId == albumId) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCredit = tx.kind.isCredit;
    final sign = isCredit ? '+' : '';
    final amountColor =
        isCredit ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    final history = ref.watch(historyProvider);
    final album = _resolveAlbum(history);
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
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    timeago.format(tx.createdAt, locale: 'ko'),
                    style:
                        TextStyle(color: AppTheme.textHint, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$sign${tx.amount}',
                    style: TextStyle(
                        color: amountColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                Text('잔액 ${tx.balanceAfter}',
                    style: TextStyle(
                        color: AppTheme.textHint, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TxLeading extends StatelessWidget {
  final CoinTransaction tx;
  final FaceReadingReport? album;
  const _TxLeading({required this.tx, required this.album});

  @override
  Widget build(BuildContext context) {
    final path = album?.thumbnailPath;
    if (path != null && path.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _txIconAvatar(tx),
        ),
      );
    }
    return _txIconAvatar(tx);
  }
}

Widget _txIconAvatar(CoinTransaction tx) {
  return CircleAvatar(
    radius: 18,
    backgroundColor: Colors.white,
    child: Icon(
      switch (tx.kind) {
        CoinTxKind.purchase => Icons.add_shopping_cart_outlined,
        CoinTxKind.bonus => Icons.card_giftcard_outlined,
        CoinTxKind.refund => Icons.undo_outlined,
        CoinTxKind.spend => Icons.remove_circle_outline,
      },
      color: AppTheme.textSecondary,
      size: 20,
    ),
  );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text('아직 거래 내역이 없습니다',
            style: TextStyle(color: AppTheme.textHint, fontSize: 13)),
      ),
    );
  }
}

class _LoggedOutView extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoggedOutView({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wallet_outlined,
                color: AppTheme.textHint, size: 56),
            const SizedBox(height: 16),
            Text('로그인 후 지갑을 이용할 수 있습니다',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15)),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              height: 46,
              child: ElevatedButton(
                onPressed: onLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEE500),
                  foregroundColor: const Color(0xFF3C1E1E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('카카오로 로그인',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
