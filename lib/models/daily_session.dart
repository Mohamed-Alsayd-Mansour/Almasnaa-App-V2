import 'enums.dart';

/// تمثل يومية عمل كاملة (يوم إنتاج واحد داخل المصنع).
class DailySession {
  final String id;
  final String dayName;
  final DateTime date;
  final DateTime startTime;
  final DateTime? endTime;
  final DailySessionStatus status;

  /// معرّفات الملكية ولقطات الأسماء وقت إنشاء اليومية (ثابتة بعد الإنشاء).
  final String? rassasId;
  final String? supervisorId;
  final String rassasName;
  final String supervisorName;

  const DailySession({
    required this.id,
    required this.dayName,
    required this.date,
    required this.startTime,
    required this.status,
    this.endTime,
    this.rassasId,
    this.supervisorId,
    this.rassasName = '',
    this.supervisorName = '',
  });

  bool get isActive => status == DailySessionStatus.active;
  bool get isPaused => status == DailySessionStatus.paused;
  bool get isClosed => status == DailySessionStatus.closed;
  bool get isOpen => !isClosed;

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
      rassasId: rassasId,
      supervisorId: supervisorId,
      rassasName: rassasName,
      supervisorName: supervisorName,
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
      rassasId: map['rassas_id'] as String?,
      supervisorId: map['supervisor_id'] as String?,
      rassasName: map['rassas_name_snapshot'] as String? ?? '',
      supervisorName: map['supervisor_name_snapshot'] as String? ?? '',
    );
  }
}
