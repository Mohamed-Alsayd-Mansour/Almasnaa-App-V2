import 'package:almasnaa/data/supa.dart';
import 'package:almasnaa/models/daily_session.dart';
import 'package:almasnaa/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('server timestamps', () {
    test('fromServer converts UTC strings to local and toServer returns the same instant in UTC', () {
      final row = {'created_at': '2026-10-22T10:00:00+00:00', 'name': 'x'};
      final local = fromServer(row);
      final back = toServer(local);
      expect(DateTime.parse(back['created_at'] as String).isUtc, isTrue);
      expect(
        DateTime.parse(back['created_at'] as String).toUtc(),
        DateTime.utc(2026, 10, 22, 10),
      );
      expect(local['name'], 'x');
    });

    test('null timestamps stay null', () {
      expect(fromServer({'end_time': null})['end_time'], isNull);
      expect(toServer({'last_deficiency_update_at': null})['last_deficiency_update_at'], isNull);
    });
  });

  group('DailySession', () {
    test('parses paused status and owner snapshots', () {
      final s = DailySession.fromMap(fromServer({
        'id': 'a',
        'day_name': 'السبت',
        'date': '2026-10-24T00:00:00+00:00',
        'start_time': '2026-10-24T06:00:00+00:00',
        'end_time': null,
        'status': 'paused',
        'rassas_id': 'r',
        'supervisor_id': 's',
        'rassas_name_snapshot': 'منصور',
        'supervisor_name_snapshot': 'قدري',
      }));
      expect(s.status, DailySessionStatus.paused);
      expect(s.isOpen, isTrue);
      expect(s.isActive, isFalse);
      expect(s.supervisorName, 'قدري');
      expect(s.rassasId, 'r');
    });

    test('closed sessions are not open', () {
      final s = DailySession.fromMap(fromServer({
        'id': 'a',
        'day_name': 'x',
        'date': '2026-10-24T00:00:00+00:00',
        'start_time': '2026-10-24T06:00:00+00:00',
        'status': 'closed',
      }));
      expect(s.isOpen, isFalse);
      expect(s.rassasName, '');
    });
  });

  group('friendlyError', () {
    test('maps permission errors', () {
      expect(friendlyError(const PostgrestException(message: 'x', code: '42501')),
          'غير مصرح لك بهذه العملية.');
    });

    test('closed daily message', () {
      expect(friendlyError(const PostgrestException(message: 'a closed daily is read-only')),
          'اليومية مغلقة ولا يمكن تعديلها.');
    });

    test('offline errors never claim success', () {
      expect(friendlyError(Exception('SocketException: Failed host lookup')), kOfflineMessage);
    });
  });
}
