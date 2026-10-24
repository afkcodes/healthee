/// A recorded observation; timestamps are instants, displayed locally by UI.
class JournalEntry {
  const JournalEntry({
    required this.type,
    required this.at,
    this.id,
    this.name,
    this.amount,
    this.unit,
    this.notes,
  });

  factory JournalEntry.fromJson(Map<String, Object?> json) => JournalEntry(
    type: json['type']! as String,
    at: DateTime.fromMillisecondsSinceEpoch(
      (json['ts']! as num).toInt(),
      isUtc: true,
    ),
    id: json['id'] as String?,
    name: json['name'] as String?,
    amount: (json['amount'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    notes: json['notes'] as String?,
  );

  /// The server's id for this entry; absent on rows older than ids.
  final String? id;
  final String type;
  final DateTime at;
  final String? name;
  final double? amount;
  final String? unit;
  final String? notes;
}
