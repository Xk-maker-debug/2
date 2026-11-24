import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// 与「xk的工作台」自建后端通信的客户端。
///
/// 后端只有三个端点，全部复用：
///   GET  /api/store/<key>?prefix=<p>  列出/读取元数据
///   PUT  /api/store/<key>            写元数据（body 是 JSON）
///   DELETE /api/store/<key>          删元数据
///   GET/PUT /api/blob/<id>           读/写文件内容（二进制）
///   GET  /api/ping?prefix=<p>        变更检测（秒级同步用）
class ApiClient {
  final http.Client _http = http.Client();

  /// 统一超时：普通请求 15 秒，blob 传输另算。
  static const Duration _timeout = Duration(seconds: 15);

  String get _base => AppConfig.baseUrl;

  Uri _uri(String path) => Uri.parse('$_base$path');

  /// 探测后端是否在线（成功返回 true）。
  /// 用 /api/ping 而不是 /healthz：后者可能不带跨域头，App 里会失败。
  Future<bool> pingServer() async {
    try {
      final r = await http.get(_uri('/api/ping'));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 列出某个前缀下的全部元数据记录。
  /// 返回 [{ 'id': ..., 'props': {...} }, ...]，失败返回空列表。
  Future<List<Map<String, dynamic>>> list(String prefix) async {
    try {
      final r = await http.get(
        _uri('/api/store/x?prefix=${Uri.encodeComponent(prefix)}'),
        headers: {'Cache-Control': 'no-store'},
      );
      if (r.statusCode == 404) return [];
      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      rethrow;
    }
  }

  /// 写一条元数据（key 形如 file_xxx / recycle_xxx / tombstone_xxx）。
  Future<void> put(String key, Map<String, dynamic> value) async {
    final r = await http.put(
      _uri('/api/store/$key'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(value),
    );
    if (r.statusCode != 200) throw Exception('写入 $key 失败：HTTP ${r.statusCode}');
  }

  /// 删一条元数据。
  Future<void> delete(String key) async {
    final r = await http.delete(_uri('/api/store/$key'));
    if (r.statusCode != 200) throw Exception('删除 $key 失败：HTTP ${r.statusCode}');
  }

  /// 变更检测：返回该前缀下最新修改时间戳（毫秒）。
  /// App 每 2 秒调用一次，时间戳变了才拉全量，省流量。
  Future<int> latest(String prefix) async {
    try {
      final r = await http.get(
        _uri('/api/ping?prefix=${Uri.encodeComponent(prefix)}'),
        headers: {'Cache-Control': 'no-store'},
      );
      if (r.statusCode != 200) return 0;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return (j['latest'] is num) ? (j['latest'] as num).round() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 分片阈值：云端网关对单个 PUT body 卡在约 60MB（实测 67MB 被 413）。
  /// 取 50MB 留出安全余量，超过就切片传输。
  static const int _chunkSize = 50 * 1024 * 1024;

  /// 上传文件内容（二进制）。
  /// 小文件直接 PUT；大文件分片上传 + 写清单，下载端按清单重组。
  /// 分片协议：
  ///   PUT /api/blob/<id>__p<i>  每片（i 从 0 开始）
  ///   PUT /api/store/blobparts_<id>  { "n": 片数, "size": 总字节 }
  /// 桌面APP后端用同一套协议，三端互通。
  Future<void> putBlob(String id, Uint8List bytes) async {
    if (bytes.length <= _chunkSize) {
      final timeout = Duration(
        seconds: (bytes.length / (1024 * 1024) * 2 + 30).clamp(30, 600).round(),
      );
      final r = await http.put(
        _uri('/api/blob/$id'),
        headers: {'Content-Type': 'application/octet-stream'},
        body: bytes,
      );
      if (r.statusCode != 200) {
        throw Exception('文件内容上传失败：HTTP ${r.statusCode}');
      }
      return;
    }

    // 大文件：分片
    final int parts = (bytes.length / _chunkSize).ceil();
    for (var i = 0; i < parts; i++) {
      final start = i * _chunkSize;
      final end = (start + _chunkSize > bytes.length)
          ? bytes.length
          : start + _chunkSize;
      final piece = Uint8List.sublistView(bytes, start, end);
      final r = await http.put(
        _uri('/api/blob/${id}__p$i'),
        headers: {'Content-Type': 'application/octet-stream'},
        body: piece,
      );
      if (r.statusCode != 200) {
        throw Exception('第 ${i + 1}/$parts 片上传失败：HTTP ${r.statusCode}');
      }
    }
    // 写分片清单（有它才走分片读取）
    await put('blobparts_$id', {'n': parts, 'size': bytes.length});
  }

  /// 下载文件内容（二进制）。
  /// 先探测分片清单，有则分片拉取并合并；否则直接 GET 整块（兼容旧文件/网页版）。
  Future<Uint8List> getBlob(String id) async {
    // 探测分片清单
    try {
      final metaR = await http.get(
        _uri('/api/store/blobparts_$id'),
        headers: {'Cache-Control': 'no-store'},
      );
      if (metaR.statusCode == 200) {
        final j = jsonDecode(utf8.decode(metaR.bodyBytes));
        final props = j['props'];
        final obj = (props is Map) ? props : j;
        final n = (obj['n'] is num) ? (obj['n'] as num).toInt() : 0;
        if (n > 0) {
          final out = BytesBuilder(copy: true);
          for (var i = 0; i < n; i++) {
            final r = await http.get(
              _uri('/api/blob/${id}__p$i'),
              headers: {'Cache-Control': 'no-store'},
            );
            if (r.statusCode != 200) {
              throw Exception('第 ${i + 1}/$n 片读取失败：HTTP ${r.statusCode}');
            }
            out.add(r.bodyBytes);
          }
          return out.takeBytes();
        }
      }
    } catch (_) {
      // 清单读取失败 → 按整块兜底
    }

    final r = await http.get(
      _uri('/api/blob/$id'),
      headers: {'Cache-Control': 'no-store'},
    );
    if (r.statusCode != 200) {
      throw Exception('文件内容读取失败：HTTP ${r.statusCode}');
    }
    return r.bodyBytes;
  }

  /// 读取访问密码哈希（s256: 开头）。
  Future<String?> getPasswordHash() async {
    try {
      final r = await http.get(
        _uri('/api/store/setting_pwd_hash'),
        headers: {'Cache-Control': 'no-store'},
      );
      if (r.statusCode == 404) return null;
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      // 后端存的是 { id, props:{ "哈希":{text:"s256:..."} } } 或直接是值
      final props = j['props'];
      if (props is Map) {
        for (final k in ['哈希', 'hash', '值', 'value', '密码']) {
          final v = props[k];
          if (v is Map && v['text'] != null) return v['text'].toString();
          if (v != null) return v.toString();
        }
      }
      if (j['text'] != null) return j['text'].toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 计算与工作台一致的密码哈希：SHA256("xk::" + 密码)，前缀 s256:。
  static String hashPassword(String password) {
    final bytes = utf8.encode('xk::$password');
    return 's256:${sha256.convert(bytes).toString()}';
  }

  /// 校验密码是否正确。云端没设密码时视为直接放行。
  Future<bool> checkPassword(String password) async {
    final stored = await getPasswordHash();
    if (stored == null || stored.isEmpty) return true;
    final computed = hashPassword(password);
    if (stored == computed) return true;
    // 兼容旧格式：存的是纯 hex（无前缀）
    if (!stored.startsWith('s256:') && computed.startsWith('s256:')) {
      return stored == computed.substring(5);
    }
    return false;
  }

  void dispose() => _http.close();
}
