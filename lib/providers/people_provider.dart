import 'package:flutter/foundation.dart';

import '../models/person.dart';
import '../repositories/person_repository.dart';

/// يدير قوائم الأسماء المستخدمة كخيارات في نماذج اليومية، ويُعدَّل
/// محتواها من تبويب الإعدادات.
class PeopleProvider extends ChangeNotifier {
  final PersonRepository _repository;

  PeopleProvider({PersonRepository? repository})
      : _repository = repository ?? PersonRepository();

  List<Person> _all = [];
  String? errorMessage;

  List<Person> get all => _all;

  List<Person> byRole(PersonRole role) =>
      _all.where((p) => p.role == role).toList();

  List<String> namesFor(PersonRole role) =>
      byRole(role).map((p) => p.name).toList();

  Future<void> load() async {
    try {
      _all = await _repository.getAll();
      errorMessage = null;
    } catch (e) {
      errorMessage = 'تعذر تحميل قوائم الأسماء: $e';
    }
    notifyListeners();
  }

  void _sort() =>
      _all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// يُرجع رسالة خطأ عند الفشل، أو null عند النجاح.
  Future<String?> add({required String name, required PersonRole role}) async {
    if (name.trim().isEmpty) return 'الاسم مطلوب.';
    try {
      if (await _repository.isNameTaken(name, role)) {
        return 'هذا الاسم موجود بالفعل في قائمة ${role.label}.';
      }
      final person = await _repository.create(name: name, role: role);
      _all = [..._all, person];
      _sort();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر حفظ الاسم: $e';
    }
  }

  Future<String?> update({
    required Person original,
    required String name,
    required PersonRole role,
  }) async {
    if (name.trim().isEmpty) return 'الاسم مطلوب.';
    try {
      if (await _repository.isNameTaken(name, role, excludingId: original.id)) {
        return 'هذا الاسم موجود بالفعل في قائمة ${role.label}.';
      }
      final updated = await _repository
          .update(original.copyWith(name: name.trim(), role: role));
      _all = _all.map((p) => p.id == updated.id ? updated : p).toList();
      _sort();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تعديل الاسم: $e';
    }
  }

  Future<String?> delete(String id) async {
    try {
      await _repository.delete(id);
      _all = _all.where((p) => p.id != id).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر حذف الاسم: $e';
    }
  }
}
