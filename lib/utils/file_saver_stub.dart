import 'dart:typed_data';

/// نتيجة محاولة الحفظ: [saved] = false تعني أن المستخدم ألغى النافذة (ليس خطأ).
class SaveResult {
  const SaveResult({required this.saved});
  final bool saved;
}

/// تنفيذ احتياطي لمنصة غير معروفة.
Future<SaveResult> saveBytesAsFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
  String dialogTitle = 'حفظ الملف',
}) async {
  throw UnsupportedError('حفظ الملفات غير مدعوم على هذه المنصة.');
}
