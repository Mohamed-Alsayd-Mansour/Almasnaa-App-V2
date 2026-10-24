import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:almasnaa/models/chat.dart';
import 'package:almasnaa/utils/chat_files.dart';

void main() {
  const c = '11111111-1111-4111-8111-111111111111';
  const m = '22222222-2222-4222-8222-222222222222';
  const a = '33333333-3333-4333-8333-333333333333';

  PendingAttachment att(String name) => PendingAttachment(
        id: a,
        messageId: m,
        conversationId: c,
        bytes: Uint8List(3),
        fileName: name,
        mimeType: 'application/pdf',
        kind: MsgKind.file,
      );

  test('storage path matches <conversation>/<message>/<attachment>_name and is ASCII-safe', () {
    final p = att('تقرير الغرفة (نهائي).pdf').storagePath;
    expect(p.startsWith('$c/$m/${a}_'), isTrue);
    expect(p.endsWith('.pdf'), isTrue);
    expect(RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(p), isTrue);
  });

  test('file validation mirrors server rules', () {
    expect(ChatFiles.validate('a.exe', 10), isNotNull);
    expect(ChatFiles.validate('a.png', 11 * 1024 * 1024), isNotNull);
    expect(ChatFiles.validate('a.PDF', 100), isNull);
    expect(ChatFiles.validate('a.docx', 0), isNotNull);
    expect(ChatFiles.kindForMime('video/mp4'), MsgKind.video);
  });
}
