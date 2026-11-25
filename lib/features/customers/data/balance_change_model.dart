/// Immutable audit entry for one exact customer-balance change.
class BalanceChangeRecord {
  const BalanceChangeRecord({
    required this.id,
    required this.customerId,
    required this.previousBalance,
    required this.newBalance,
    required this.reason,
    required this.changedBy,
    required this.changedAt,
  });

  final String id;
  final String customerId;
  final String previousBalance;
  final String newBalance;
  final String reason;
  final String? changedBy;
  final String changedAt;

  factory BalanceChangeRecord.fromMap(Map<String, Object?> row) {
    return BalanceChangeRecord(
      id: row['id']! as String,
      customerId: row['customer_id']! as String,
      previousBalance: row['previous_balance']! as String,
      newBalance: row['new_balance']! as String,
      reason: row['reason']! as String,
      changedBy: row['changed_by'] as String?,
      changedAt: row['changed_at']! as String,
    );
  }
}

class BalanceValidationException implements Exception {
  const BalanceValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
