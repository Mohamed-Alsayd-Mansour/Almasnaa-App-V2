import 'package:intl/intl.dart';

/// أدوات تنسيق موحّدة للتاريخ والوقت بالعربية تُستخدم في كل الشاشات.
class AppDateFormatter {
  AppDateFormatter._();

  static const _arabicDayNames = {
    DateTime.saturday: 'السبت',
    DateTime.sunday: 'الأحد',
    DateTime.monday: 'الاثنين',
    DateTime.tuesday: 'الثلاثاء',
    DateTime.wednesday: 'الأربعاء',
    DateTime.thursday: 'الخميس',
    DateTime.friday: 'الجمعة',
  };

  /// اسم اليوم بالعربية (مثال: السبت).
  static String dayName(DateTime date) =>
      _arabicDayNames[date.weekday] ?? '';

  /// التاريخ بصيغة يوم/شهر/سنة (مثال: 03/10/2026).
  static String date(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  /// الوقت بصيغة 12 ساعة مع صباحًا/مساءً (مثال: 08:05 ص).
  static String time(DateTime time) {
    final hour24 = time.hour;
    final period = hour24 < 12 ? 'ص' : 'م';
    int hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final hourStr = hour12.toString().padLeft(2, '0');
    return '$hourStr:$minute $period';
  }

  /// نص وقت الانتهاء أو "لم تنتهِ بعد" إذا كانت اليومية ما زالت نشطة.
  static String endTimeOrPending(DateTime? endTime) {
    if (endTime == null) return 'لم تنتهِ بعد';
    return time(endTime);
  }

  static String dateTime(DateTime dt) => '${date(dt)} - ${time(dt)}';
}
