import 'package:shared_preferences/shared_preferences.dart';

/// 应用配置：后端地址集中在这里管理。
///
/// 【重要 · 2026-11-23 改为云端中转】
/// 数据源 = 云端 ee6724b3（与网页版、桌面APP共用同一个数据池）。
/// 这样手机不需要和电脑同时在线：任一设备上传/删除都直接落云端，
/// 另一设备上线后自动看到。彻底甩掉"同一WiFi + 电脑必须开机"的限制。
///
/// 云端地址是固定的公网地址，默认已填好，一般不用改。
class AppConfig {
  static const String _prefKey = 'backend_base_url';

  /// 云端中转站地址（固定公网，无需电脑在线）。
  static const String cloudBaseUrl =
      'https://ee6724b361024828b9712f447c688b85.app.workbuddy.host';

  /// 默认地址 = 云端。
  static const String defaultBaseUrl = cloudBaseUrl;

  static String _baseUrl = defaultBaseUrl;

  /// 当前后端地址（内存缓存）。
  static String get baseUrl => _baseUrl;

  /// 是否正在使用云端中转（而非自建/局域网后端）。
  static bool get isCloud => _baseUrl.contains('workbuddy.host');

  /// 从本地存储加载地址（App 启动时调用一次）。
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_prefKey) ?? defaultBaseUrl;
  }

  /// 保存新地址，并立即生效。
  static Future<void> save(String url) async {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    _baseUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, normalized);
  }

  /// 恢复为默认云端地址。
  static Future<void> resetToCloud() async {
    await save(cloudBaseUrl);
  }
}
