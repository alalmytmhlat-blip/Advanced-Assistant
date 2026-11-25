class ReminderRecord {
  const ReminderRecord({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.note,
    this.customerId,
    this.customerName,
    this.assignedTo,
    this.assigneeName,
    this.completedAt,
  });
  final String id;
  final String title;
  final String? note;
  final String? customerId;
  final String? customerName;
  final DateTime dueAt;
  final String priority;
  final String status;
  final String? assignedTo;
  final String? assigneeName;
  final DateTime createdAt;
  final DateTime? completedAt;

  factory ReminderRecord.fromMap(Map<String, Object?> map) => ReminderRecord(
        id: map['id']! as String,
        title: map['title']! as String,
        note: map['note'] as String?,
        customerId: map['customer_id'] as String?,
        customerName: map['customer_name'] as String?,
        dueAt: DateTime.parse(map['due_at']! as String).toLocal(),
        priority: map['priority']! as String,
        status: map['status']! as String,
        assignedTo: map['assigned_to'] as String?,
        assigneeName: map['assignee_name'] as String?,
        createdAt: DateTime.parse(map['created_at']! as String).toLocal(),
        completedAt: map['completed_at'] == null
            ? null
            : DateTime.parse(map['completed_at']! as String).toLocal(),
      );
}

class ReminderCustomer {
  const ReminderCustomer({required this.id, required this.name});
  final String id;
  final String name;
}
