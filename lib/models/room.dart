/// بيانات الغرفة الأساسية كما هي مسجلة في تبويب "الغرف".
///
/// ملاحظة مهمة: هذا الكيان قابل للتعديل بحرية، لكن تعديله لاحقًا
/// لا يجب أن يغيّر أي Snapshot محفوظ مسبقًا داخل [DailyEntry].
class Room {
  final String id;
  final String name;
  final int pieceCount;
  final int glassPieceCount;

  /// عدد قطع القواطيع (قيمة افتراضية 0 للغرف المسجلة قبل إضافة الحقل).
  final int partitionPieceCount;

  /// عدد قواطيع الغرفة (رقم للعرض فقط، لا يدخل في أي مجموع).
  final int partitionCount;

  /// عدد قطع الرخام (قيمة افتراضية 0 للغرف المسجلة قبل إضافة الحقل).
  final int marblePieceCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Room({
    required this.id,
    required this.name,
    required this.pieceCount,
    required this.glassPieceCount,
    this.partitionPieceCount = 0,
    this.partitionCount = 0,
    this.marblePieceCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// عدد القطع الكلي = قطع الخشب + القواطيع + الزجاج + الرخام.
  int get totalPieceCount =>
      pieceCount + partitionPieceCount + glassPieceCount + marblePieceCount;

  /// عدد ورق الطباعة = قطع الخشب + قطع القواطيع.
  int get printPaperCount => pieceCount + partitionPieceCount;

  /// نص العرض: قطع القواطيع ثم عددها بين قوسين، مثال: 1 (11).
  String get partitionDisplay => '$partitionPieceCount ($partitionCount)';

  Room copyWith({
    String? name,
    int? pieceCount,
    int? glassPieceCount,
    int? partitionPieceCount,
    int? partitionCount,
    int? marblePieceCount,
    DateTime? updatedAt,
  }) {
    return Room(
      id: id,
      name: name ?? this.name,
      pieceCount: pieceCount ?? this.pieceCount,
      glassPieceCount: glassPieceCount ?? this.glassPieceCount,
      partitionPieceCount: partitionPieceCount ?? this.partitionPieceCount,
      partitionCount: partitionCount ?? this.partitionCount,
      marblePieceCount: marblePieceCount ?? this.marblePieceCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'piece_count': pieceCount,
      'glass_piece_count': glassPieceCount,
      'partition_piece_count': partitionPieceCount,
      'partition_count': partitionCount,
      'marble_piece_count': marblePieceCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Room.fromMap(Map<String, Object?> map) {
    return Room(
      id: map['id'] as String,
      name: map['name'] as String,
      pieceCount: map['piece_count'] as int,
      glassPieceCount: map['glass_piece_count'] as int,
      partitionPieceCount: map['partition_piece_count'] as int? ?? 0,
      partitionCount: map['partition_count'] as int? ?? 0,
      marblePieceCount: map['marble_piece_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
