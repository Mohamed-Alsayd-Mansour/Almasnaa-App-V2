import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'file_saver_stub.dart' show SaveResult;
export 'file_saver_stub.dart' show SaveResult;

/// المنصات ذات نظام الملفات: نافذة الحفظ الأصلية، ثم نكتب الملف بأنفسنا لأن بعض
/// إصدارات FilePicker.saveFile على سطح المكتب تُعيد المسار دون كتابة الملف.
/// السلوك السابق لـ Android وWindows دون تغيير.
Future<SaveResult> saveBytesAsFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
  String dialogTitle = 'حفظ الملف',
}) async {
  final dot = fileName.lastIndexOf('.');
  final ext = dot > 0 ? fileName.substring(dot + 1) : null;
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: ext == null ? FileType.any : FileType.custom,
    allowedExtensions: ext == null ? null : [ext],
    bytes: bytes,
  );
  if (path == null) return const SaveResult(saved: false);
  await File(path).writeAsBytes(bytes);
  return const SaveResult(saved: true);
}
