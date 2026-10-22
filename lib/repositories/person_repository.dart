import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/person.dart';

/// قراءة/كتابة قوائم الأسماء (الخدمة، النجار، الرصيص، المشرف، الرميم).
class PersonRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  PersonRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  Future<List<Person>> _readAll() async {
    final rows = await _db.readList(AppDatabase.peopleKey);
    return rows.map(Person.fromMap).toList();
  }

  Future<void> _writeAll(List<Person> people) async {
    await _db.writeList(
      AppDatabase.peopleKey,
      people.map((p) => p.toMap()).toList(),
    );
  }

  Future<List<Person>> getAll() async {
    final people = await _readAll();
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return people;
  }

  Future<Person> create({required String name, required PersonRole role}) async {
    final person = Person(
      id: _uuid.v4(),
      name: name.trim(),
      role: role,
      createdAt: DateTime.now(),
    );
    final people = await _readAll();
    people.add(person);
    await _writeAll(people);
    return person;
  }

  Future<Person> update(Person person) async {
    final people = await _readAll();
    final idx = people.indexWhere((p) => p.id == person.id);
    if (idx == -1) throw StateError('الاسم غير موجود.');
    people[idx] = person;
    await _writeAll(people);
    return person;
  }

  Future<void> delete(String id) async {
    final people = await _readAll();
    people.removeWhere((p) => p.id == id);
    await _writeAll(people);
  }

  Future<bool> isNameTaken(String name, PersonRole role,
      {String? excludingId}) async {
    final people = await _readAll();
    final target = name.trim().toLowerCase();
    return people.any((p) =>
        p.role == role &&
        p.name.trim().toLowerCase() == target &&
        (excludingId == null || p.id != excludingId));
  }
}
