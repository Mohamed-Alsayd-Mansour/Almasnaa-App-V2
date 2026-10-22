/// يحسب عدد القطع الناقصة اعتمادًا على نص النواقص فقط،
/// وفق القاعدة الثابتة في مواصفات التطبيق:
///
/// - نص فارغ (أو مسافات فقط)  => 0
/// - نص غير فارغ              => عدد علامات "-" + 1
///
/// هذه الدالة هي المصدر الوحيد للحقيقة لحساب العدد، ويُمنع تعديل
/// العدد يدويًا من أي مكان آخر في التطبيق.
int calculateMissingPiecesCount(String? deficiencyText) {
  final text = deficiencyText?.trim() ?? '';
  if (text.isEmpty) return 0;
  final dashCount = '-'.allMatches(text).length;
  return dashCount + 1;
}
