import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../api/api_client.dart';
import '../models/file_item.dart';
import 'offline_queue.dart';

/// 文件仓库：把 API 层的原始端点封装成「文件级」的业务操作。
/// 严格遵循工作台铁律：
///   1) 删除只删元数据 + 写墓碑 + 写回收站，绝不删 blob（留 7 天可恢复）
///   2) 列表要过滤墓碑，删掉的不再出现
class FileRepository {
  final ApiClient api;

  /// 离线操作队列：网络失败时暂存，联网后补传。
  final OfflineQueue offline = OfflineQueue();

  FileRepository({ApiClient? api}) : api = api ?? ApiClient();

  /// App 启动时调用：加载离线队列并立即尝试补传。
  /// 返回本次成功补传的条数。
  Future<int> initAndDrain() async {
    await offline.load();
    if (offline.isEmpty) return 0;
    return drainPending();
  }

  /// 补传所有待处理操作（联网后 / 定时器调用）。
  Future<int> drainPending() => offline.drain(
        uploadFn: (op) async {
          final bytes = base64Decode(op['bytesBase64'] as String);
          await api.putBlob(op['id'] as String, bytes);
          final item = FileItem(
            id: op['id'] as String,
            name: op['name'] as String,
            category: '速传',
            kind: _isText(op['mime'] as String) ? 'text' : 'binary',
            size: bytes.length,
            mime: op['mime'] as String,
            storedIn: 'blob',
            path: op['path'] as String? ?? '',
            source: '手机',
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          );
          await api.put('file_${op['id']}', item.toRecord());
        },
        deleteFn: (op) async {
          await api.put('recycle_${op['id']}', Map<String, dynamic>.from(op['recycle'] as Map));
          await api.put('tombstone_file_${op['id']}', Map<String, dynamic>.from(op['tombstone'] as Map));
          await api.delete('file_${op['id']}');
        },
      );

  /// 当前待补传条数。
  int get pendingCount => offline.length;

  /// 墓碑记录（本地缓存），key 形如 file_<id>。
  Map<String, dynamic> _tombstones = {};

  /// 拉取全部文件（已过滤墓碑）。
  Future<List<FileItem>> loadFiles() async {
    await _loadTombstones();
    final records = await api.list('file_');
    final result = <FileItem>[];
    for (final rec in records) {
      final f = FileItem.fromRecord(rec);
      if (f.id.isEmpty) continue;
      // 墓碑过滤：删过的文件不再显示
      if (_tombstones.containsKey('file_${f.id}') ||
          _tombstones.containsKey(f.id)) {
        continue;
      }
      result.add(f);
    }
    return result;
  }

  /// 读取墓碑。后端墓碑键是 tombstone_<类型>_<id>（与工作台一致）。
  Future<void> _loadTombstones() async {
    try {
      final records = await api.list('tombstone_');
      final map = <String, dynamic>{};
      for (final rec in records) {
        final id = rec['id']?.toString() ?? '';
        final props = rec['props'] is Map
            ? Map<String, dynamic>.from(rec['props'] as Map)
            : <String, dynamic>{};
        // 从 props 里取被删的实体 id 和类型
        final entityId = _propText(props, '实体ID');
        final type = _propText(props, '类型');
        if (entityId.isNotEmpty) {
          map['${type}_$entityId'] = true;
          map[entityId] = true;
        }
        if (id.isNotEmpty) map[id] = true;
      }
      _tombstones = map;
    } catch (_) {
      // 墓碑读取失败不应阻断列表，但为安全起见保留上次结果
    }
  }

  /// 上传：先写文件内容(blob)，再写元数据(file_<id>)，来源标记为"手机"。
  /// [onProgress] 回调 0.0~1.0，用于显示进度条。
  Future<FileItem> upload({
    required String name,
    required Uint8List bytes,
    required String mime,
    String path = '',
    void Function(double)? onProgress,
  }) async {
    final id = 'f_${DateTime.now().microsecondsSinceEpoch}'
        '${(100 + DateTime.now().microsecond % 900)}';

    final item = FileItem(
      id: id,
      name: name,
      category: '速传',
      kind: _isText(mime) ? 'text' : 'binary',
      size: bytes.length,
      mime: mime,
      storedIn: 'blob',
      path: path,
      source: '手机',
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    onProgress?.call(0.05);
    try {
      await api.putBlob(id, bytes);
      onProgress?.call(0.85);
      await api.put('file_$id', item.toRecord());
      onProgress?.call(1.0);
    } catch (_) {
      // 断网/云端暂不可达 → 整单入队，联网后补传（手机不必等电脑在线）
      await offline.enqueueUpload(
        id: id, name: name, mime: mime, path: path, bytes: bytes,
      );
      onProgress?.call(1.0);
    }
    return item;
  }

  /// 下载文件内容。
  Future<Uint8List> download(FileItem f) => api.getBlob(f.id);

  /// 删除：只删元数据 + 写墓碑 + 写回收站，保留 blob 内容（7 天内可恢复）。
  Future<void> delete(FileItem f) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // 1) 写回收站（recycle_<id>），留 7 天
    final recycleRec = {
      'id': 'recycle_${f.id}',
      'props': {
        '实体ID': {'text': f.id},
        '删除时间': {'date': now},
        '名称': {'text': f.name},
        '相对路径': {'text': f.path},
        '项目ID': {'text': f.projectId},
        '项目名称': {'text': ''},
        '分类': {'text': f.category},
        '文件类型': {'text': f.kind},
        'MIME': {'text': f.mime},
        '大小': {'number': f.size},
        '来源': {'text': f.source},
        '存储位置': {'text': f.storedIn},
        '原更新时间': {'date': f.updatedAt},
      }
    };

    // 2) 写墓碑（tombstone_file_<id>）—— 两端都靠它判断"已删"
    final tombstoneRec = {
      'id': 'tombstone_file_${f.id}',
      'props': {
        '实体ID': {'text': f.id},
        '类型': {'text': 'file'},
        '删除时间': {'date': now},
      }
    };

    try {
      await api.put('recycle_${f.id}', recycleRec);
      await api.put('tombstone_file_${f.id}', tombstoneRec);
      await api.delete('file_${f.id}');
    } catch (_) {
      // 断网 → 删除操作入队，联网后补传（幂等：墓碑/回收站覆盖写、删元数据可重复）
      await offline.enqueueDelete(
        id: f.id, recycle: recycleRec, tombstone: tombstoneRec,
      );
    }

    // 本地墓碑立即生效：即使还没补传成功，这个文件也在本机列表消失
    // 🔴 绝不调 api.deleteBlob —— 内容要留住，回收站 7 天内可恢复
    _tombstones['file_${f.id}'] = true;
  }

  /// 监听某个前缀是否变化（配合定时器做秒级同步）。
  Future<int> fileLatest() => api.latest('file_');

  void dispose() => api.dispose();

  static bool _isText(String mime) =>
      mime.startsWith('text/') ||
      mime == 'application/json' ||
      mime == 'application/xml';

  static String _propText(Map<String, dynamic> props, String key) {
    final v = props[key];
    if (v == null) return '';
    if (v is Map) return (v['text'] ?? v['date'] ?? '').toString();
    return v.toString();
  }
}
