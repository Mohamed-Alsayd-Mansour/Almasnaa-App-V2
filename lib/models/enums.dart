/// حالة اليومية: مختارة حاليًا (active) أو معلّقة (paused) أو مغلقة.
enum DailySessionStatus {
  active,
  paused,
  closed;

  String get dbValue => name;

  static DailySessionStatus fromDb(String value) =>
      DailySessionStatus.values.firstWhere((e) => e.name == value);

  String get label => switch (this) {
        DailySessionStatus.active => 'مختارة',
        DailySessionStatus.paused => 'معلّقة',
        DailySessionStatus.closed => 'مغلقة',
      };
}

/// حالة الغرفة داخل السجل: مشتقة دائمًا من قيمة النواقص الحالية،
/// وليست قيمة مخزّنة يتم التلاعب بها يدويًا.
enum RoomEntryStatus {
  completed,
  pending;

  String get label => switch (this) {
        RoomEntryStatus.completed => 'مكتملة',
        RoomEntryStatus.pending => 'بها نواقص',
      };
}

/// شكل الغرفة في البحث المتقدم: عادية، أو غرفة بوسم "مواصفات"،
/// أو إدخال بوسم "جزء من غرفة".
enum RoomShape {
  regular,
  specs,
  partial;

  String get label => switch (this) {
        RoomShape.regular => 'عادية',
        RoomShape.specs => 'مواصفات',
        RoomShape.partial => 'جزء من غرفة',
      };
}

/// ملكية الغرفة في البحث المتقدم: داخلية، خارجية، أو أوردر (طلب مخصوص).
enum RoomOwnership {
  internal,
  external,
  order;

  String get label => switch (this) {
        RoomOwnership.internal => 'داخلية',
        RoomOwnership.external => 'خارجية',
        RoomOwnership.order => 'أوردر',
      };
}
