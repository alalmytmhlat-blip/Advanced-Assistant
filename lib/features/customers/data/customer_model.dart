/// Customer directory record. Balances remain stored as exact decimal text.
class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    required this.currentBalance,
    required this.isArchived,
    this.phone,
    this.address,
    this.category,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? category;
  final String? notes;
  final String currentBalance;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  factory CustomerRecord.fromMap(Map<String, Object?> row) {
    return CustomerRecord(
      id: row['id']! as String,
      name: row['name']! as String,
      phone: row['phone'] as String?,
      address: row['address'] as String?,
      category: row['category'] as String?,
      notes: row['notes'] as String?,
      currentBalance: row['current_balance']! as String,
      isArchived: row['is_archived'] == 1,
      createdAt: row['created_at']! as String,
      updatedAt: row['updated_at']! as String,
    );
  }
}

/// Editable customer fields. Current balance is intentionally not editable here.
class CustomerDraft {
  const CustomerDraft({
    required this.name,
    this.phone,
    this.address,
    this.category,
    this.notes,
  });

  final String name;
  final String? phone;
  final String? address;
  final String? category;
  final String? notes;
}
