/// إعدادات الاتصال بـ Supabase. تُمرَّر وقت البناء:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=...
/// مفتاح anon مفتاح عام بطبيعته (الحماية الفعلية عبر RLS). لا يوضع هنا أبدًا مفتاح service_role.
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
