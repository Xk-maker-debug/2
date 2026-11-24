import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// 离线操作队列 —— 实现"手机和电脑不需要同时在线"的另一半。
///
/// 每当上传/删除因网络失败时，把操作落盘到本地队列；App 恢复联网（或下次启动）
/// 时调用 [drain] 逐条补传。补传成功后从队列移除。
///
/// 队列条目是 JSON：
///   { kind: 'upload', id, name, mime, path, bytesBase64, createdAt }
///   { kind: 'delete', id, recycle: {...}, tombstone: {...}, createdAt }
///
/// 铁律：删除只写墓碑 + 回收站，不删 blob —— 队列补传也照此办理。
class OfflineQueue {
  static const String _prefKey = 'xk_offline_ops_v1';
  List<Map<String, dynamic>> _ops = [];

  /// 从本地存储加载队列。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) {
      _ops = [];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _ops = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {
      _ops = [];
    }
  }

  int get length => _ops.length;
  bool get isEmpty => _ops.isEmpty;

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_ops));
  }

  /// 入队一个上传操作（文件字节以 base64 落盘）。
  Future<void> enqueueUpload({
    required String id,
    required String name,
    required String mime,
    required String path,
    required Uint8List bytes,
  }) async {
    _ops.add({
      'kind': 'upload',
      'id': id,
      'name': name,
      'mime': mime,
      'path': path,
      'bytesBase64': base64Encode(bytes),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _save();
  }

  /// 入队一个删除操作。
  Future<void> enqueueDelete({
    required String id,
    required Map<String, dynamic> recycle,
    required Map<String, dynamic> tombstone,
  }) async {
    _ops.add({
      'kind': 'delete',
      'id': id,
      'recycle': recycle,
      'tombstone': tombstone,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _save();
  }

  /// 补传全部待处理操作。
  /// [uploadFn] / [deleteFn] 是实际执行上传/删除的回调（挂在 FileRepository 上）。
  /// 返回成功补传的条数；失败的留在队列里下次再试。
  Future<int> drain({
    required Future<void> Function(Map<String, dynamic> op) uploadFn,
    required Future<void> Function(Map<String, dynamic> op) deleteFn,
  }) async {
    if (_ops.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    int done = 0;
    for (final op in List<Map<String, dynamic>>.from(_ops)) {
      try {
        if (op['kind'] == 'upload') {
          await uploadFn(op);
        } else if (op['kind'] == 'delete') {
          await deleteFn(op);
        } else {
          continue; // 未知类型，丢弃
        }
        done++;
      } catch (_) {
        remaining.add(op); // 网络仍未恢复，保留
      }
    }
    _ops = remaining;
    await _save();
    return done;
  }

  /// 清空队列（谨慎：仅在用户确认放弃本地待传操作时调用）。
  Future<void> clear() async {
    _ops = [];
    await _save();
  }
}
