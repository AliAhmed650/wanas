/// إعدادات Supabase Storage (مكان تخزين الصور والفيديوهات والملفات والريكوردات).
///
/// الـ anon key مصمَّم إنه يكون ظاهر في التطبيق (مش سر)، والحماية الفعلية
/// بتيجي من سياسات الـ bucket (بتسمح بالرفع بس، ومفيش حذف ولا تعديل ولا list).
/// خد القيمتين من: Supabase Dashboard ← Project Settings ← API.
class SupabaseConfig {
  /// مثال: https://abcdefghijklmno.supabase.co
  static const String url = 'wtsopfvekdxlehrvtnbm.co';

  /// الـ "anon public" key (ماتحطش الـ service_role key هنا أبدًا)
  static const String anonKey = 'sb_publishable_SEwKBg9jq0W4I0602VxBoA_x8SpfVcZ';

  /// اسم الـ bucket اللي هتعمله في Supabase
  static const String bucket = 'chat-media';

  static bool get isConfigured =>
      url.startsWith('https://') && !url.contains('PUT_YOUR') &&
      !anonKey.contains('PUT_YOUR');
}
