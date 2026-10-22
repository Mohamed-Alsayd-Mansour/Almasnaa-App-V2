import 'package:flutter_test/flutter_test.dart';
import 'package:almasnaa/auth/app_user.dart';

void main() {
  group('AppRole', () {
    test('maps each database role to its expected label', () {
      expect(AppRole.fromDb('admin'), AppRole.admin);
      expect(AppRole.fromDb('rassas'), AppRole.rassas);
      expect(AppRole.fromDb('supervisor'), AppRole.supervisor);
      expect(AppRole.admin.label, 'الأدمن');
      expect(AppRole.rassas.label, 'الرصيص');
      expect(AppRole.supervisor.label, 'المشرف');
    });

    test('maps roles to stable database values', () {
      expect(AppRole.admin.dbValue, 'admin');
      expect(AppRole.rassas.dbValue, 'rassas');
      expect(AppRole.supervisor.dbValue, 'supervisor');
    });
  });

  group('AppUser', () {
    const user = AppUser(
      id: 'user-uuid',
      username: 'mansour',
      displayName: 'منصور',
      role: AppRole.rassas,
      mustChangePassword: true,
    );

    test('parses profile fields', () {
      final parsed = AppUser.fromMap({
        'id': 'user-uuid',
        'username': 'mansour',
        'display_name': 'منصور',
        'role': 'rassas',
        'must_change_password': true,
      });

      expect(parsed.id, 'user-uuid');
      expect(parsed.username, 'mansour');
      expect(parsed.displayName, 'منصور');
      expect(parsed.role, AppRole.rassas);
      expect(parsed.mustChangePassword, isTrue);
    });

    test('copyWith changes only the requested field', () {
      final updated = user.copyWith(mustChangePassword: false);

      expect(updated.id, user.id);
      expect(updated.username, user.username);
      expect(updated.displayName, user.displayName);
      expect(updated.role, user.role);
      expect(updated.mustChangePassword, isFalse);
    });

    test('copyWith preserves values when no changes are supplied', () {
      final updated = user.copyWith();

      expect(updated.id, user.id);
      expect(updated.username, user.username);
      expect(updated.displayName, user.displayName);
      expect(updated.role, user.role);
      expect(updated.mustChangePassword, isTrue);
    });
  });
}
