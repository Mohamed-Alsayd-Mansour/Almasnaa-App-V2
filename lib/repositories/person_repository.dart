import 'package:uuid/uuid.dart';

import '../data/supa.dart';
import '../models/person.dart';

/// قوائم الأسماء التشغيلية على الخادم (الأدمن والمشرف يكتبان، الرصيص قراءة).
class PersonRepository {
  final _uuid = const Uuid();

  Future<List<Person>> getAll() async {
    final rows = await fetchAll((from, to) =>
        supa.from('people').select().order('name').range(from, to));
    final people = rows.map((r) => Person.fromMap(fromServer(r))).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return people;
  }

  Future<Person> create({required String name, required PersonRole role}) async {
    final person = Person(
      id: _uuid.v4(),
      name: name.trim(),
      role: role,
      createdAt: DateTime.now(),
    );
    await supa
        .from('people')
        .upsert(toServer(person.toMap())..remove('created_at'),
            onConflict: 'id', ignoreDuplicates: true);
    return person;
  }

  Future<Person> update(Person person) async {
    final rows = await supa
        .from('people')
        .update({'name': person.name.trim(), 'role': person.role.dbValue})
        .eq('id', person.id)
        .select('id');
    if (rows.isEmpty) throw StateError('الاسم غير موجود أو غير مصرح بتعديله.');
    return person;
  }

  Future<void> delete(String id) async {
    final rows = await supa.from('people').delete().eq('id', id).select('id');
    if (rows.isEmpty) throw StateError('تعذر الحذف (غير موجود أو غير مصرح).');
  }

  Future<bool> isNameTaken(String name, PersonRole role, {String? excludingId}) async {
    final people = await getAll();
    final target = name.trim().toLowerCase();
    return people.any((p) =>
        p.role == role &&
        p.name.trim().toLowerCase() == target &&
        (excludingId == null || p.id != excludingId));
  }
}
