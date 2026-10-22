import 'enums.dart';

/// تمثل يومية عمل كاملة (يوم إنتاج واحد داخل المصنع).
class DailySession {
  final String id;
  final String dayName;
  final DateTime date;
  final DateTime startTime;
  final DateTime? endTime;
  final DailySessionStatus status;

  const DailySession({
    required this.id,
    required this.dayName,
    required this.date,
    required this.startTime,
    required this.status,
    this.endTime,
  });

  bool get isActive => status == DailySessionStatus.active;

  DailySession copyWith({
    DateTime? endTime,
    DailySessionStatus? status,
  }) {
    return DailySession(
      id: id,
      dayName: dayName,
      date: date,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'day_name': dayName,
      'date': date.toIso8601String(),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'status': status.dbValue,
    };
  }

  factory DailySession.fromMap(Map<String, Object?> map) {
    return DailySession(
      id: map['id'] as String,
      dayName: map['day_name'] as String,
      date: DateTime.parse(map['date'] as String),
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] == null
          ? null
          : DateTime.parse(map['end_time'] as String),
      status: DailySessionStatus.fromDb(map['status'] as String),
    );
  }
}
