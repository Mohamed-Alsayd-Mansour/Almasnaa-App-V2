/// يوفر writeBytesToPath بتنفيذ مختلف حسب المنصة: كتابة فعلية عبر
/// dart:io على كل المنصات التي تملك نظام ملفات (بما فيها Windows)،
/// ولا شيء على الويب (حيث dart:io غير متاح أصلًا، ومحاولة استيراده
/// مباشرة تكسر بناء الويب بالكامل).
export 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart';
