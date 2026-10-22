/// دور الشخص داخل المصنع. كل دور له قائمة أسماء مستقلة تُستخدم كخيارات
/// عند تسجيل غرفة في اليومية.
enum PersonRole {
  service,
  carpenter,
  installer,
  supervisor,
  repairer,
  wrapLocation;

  String get dbValue => name;

  static PersonRole fromDb(String value) =>
      PersonRole.values.firstWhere((e) => e.name == value);

  /// اسم الدور كما يظهر في عناوين الأقسام.
  String get label => switch (this) {
        PersonRole.service => 'الخدمة',
        PersonRole.carpenter => 'النجار',
        PersonRole.installer => 'الرصيص',
        PersonRole.supervisor => 'المشرف',
        PersonRole.repairer => 'الرميم',
        PersonRole.wrapLocation => 'مكان اللف',
      };

  /// عنوان الحقل في نماذج اليومية.
  String get fieldLabel =>
      this == PersonRole.wrapLocation ? label : 'اسم $label';
}

/// اسم مسجّل ضمن قائمة دور معين (نجار، مشرف، ...).
class Person {
  final String id;
  final String name;
  final PersonRole role;
  final DateTime createdAt;

  const Person({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  Person copyWith({String? name, PersonRole? role}) => Person(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'role': role.dbValue,
        'created_at': createdAt.toIso8601String(),
      };

  factory Person.fromMap(Map<String, Object?> map) => Person(
        id: map['id'] as String,
        name: map['name'] as String,
        role: PersonRole.fromDb(map['role'] as String),
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
