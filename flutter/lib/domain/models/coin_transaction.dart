enum CoinTxKind { purchase, spend, bonus, refund }

extension CoinTxKindX on CoinTxKind {
  String get wire => name;

  String get label => switch (this) {
        CoinTxKind.purchase => '충전',
        CoinTxKind.spend => '사용',
        CoinTxKind.bonus => '보너스',
        CoinTxKind.refund => '환불',
      };

  bool get isCredit => this != CoinTxKind.spend;
}

class CoinTransaction {
  final String id;
  final String userId;
  final CoinTxKind kind;
  final int amount;           // signed: credit +, debit −
  final int balanceAfter;
  final String? productId;
  final String? storeTransactionId;
  final String? referenceId;
  final String? description;
  final DateTime createdAt;

  const CoinTransaction({
    required this.id,
    required this.userId,
    required this.kind,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
    this.productId,
    this.storeTransactionId,
    this.referenceId,
    this.description,
  });

  factory CoinTransaction.fromRow(Map<String, dynamic> row) {
    return CoinTransaction(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      kind: CoinTxKind.values.firstWhere(
        (k) => k.wire == row['kind'],
        orElse: () => CoinTxKind.spend,
      ),
      amount: row['amount'] as int,
      balanceAfter: row['balance_after'] as int,
      productId: row['product_id'] as String?,
      storeTransactionId: row['store_transaction_id'] as String?,
      referenceId: row['reference_id'] as String?,
      description: row['description'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
