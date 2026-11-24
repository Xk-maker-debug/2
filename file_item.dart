/// 文件模型，字段与工作台后端的 file_<id> props 一一对应。
///
/// 后端存的形态是：
///   { "id": "f_xxx", "props": { "名称":{"text":...}, "大小":{"number":...}, ... } }
/// props 里的值是带类型的对象（text / number / date），这里在解析时拍平成普通字段。
class FileItem {
  final String id;
  final String name;
  final String projectId;
  final String category;   // 分类，手机上传的是"速传"
  final String kind;       // text / binary
  final int size;
  final String mime;
  final String storedIn;   // blob / store
  final String path;       // 相对路径（文件夹上传用）
  final String source;     // 来源：手机 / 电脑
  final String updatedAt;

  FileItem({
    required this.id,
    required this.name,
    this.projectId = '',
    this.category = '文件',
    this.kind = 'binary',
    this.size = 0,
    this.mime = '',
    this.storedIn = 'blob',
    this.path = '',
    this.source = '',
    this.updatedAt = '',
  });

  /// 是否来自手机端（用于「手机上传」分类）。
  /// 兼容旧版：category == '速传' 也算手机上传。
  bool get isFromMobile =>
      source == '手机' || category == '速传';

  /// 从后端的一条记录解析。
  /// record 形如 {"id": "...", "props": {...}}
  static FileItem fromRecord(Map<String, dynamic> record) {
    final props = record['props'] is Map
        ? Map<String, dynamic>.from(record['props'] as Map)
        : <String, dynamic>{};

    return FileItem(
      id: _text(props['实体ID']).isNotEmpty
          ? _text(props['实体ID'])
          : (record['id']?.toString() ?? ''),
      projectId: _text(props['项目ID']),
      name: _text(props['名称'], fallback: '未命名文件'),
      category: _text(props['分类'], fallback: '文件'),
      kind: _text(props['文件类型'], fallback: 'binary'),
      size: _number(props['大小']),
      mime: _text(props['MIME']),
      storedIn: _text(props['存储位置'], fallback: 'blob'),
      path: _text(props['相对路径']),
      source: _text(props['来源']),
      updatedAt: _text(props['更新时间']),
    );
  }

  /// 转成后端 props 结构（上传时用）。
  Map<String, dynamic> toProps() => {
        '实体ID': {'text': id},
        '项目ID': {'text': projectId},
        '名称': {'text': name},
        '分类': {'text': category},
        '类型': {'text': '文件'},
        '文件类型': {'text': kind == 'text' ? 'text' : 'binary'},
        '大小': {'number': size},
        'MIME': {'text': mime},
        '存储位置': {'text': storedIn == 'blob' ? 'blob' : 'store'},
        '相对路径': {'text': path},
        '来源': {'text': source},
        '更新时间': {'date': DateTime.now().toUtc().toIso8601String()},
      };

  /// 后端包装成一条记录。
  Map<String, dynamic> toRecord() => {
        'id': id,
        'props': toProps(),
      };

  /// props 里的值是 {"text": ...} / {"number": ...} / {"date": ...}，取出文本。
  static String _text(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    if (v is Map) {
      final inner = v['text'] ?? v['date'] ?? v['value'];
      return inner?.toString() ?? fallback;
    }
    return v.toString().isEmpty ? fallback : v.toString();
  }

  static int _number(dynamic v) {
    if (v is Map) {
      final inner = v['number'] ?? v['text'] ?? v['value'];
      return (inner is num) ? inner.round() : int.tryParse('$inner') ?? 0;
    }
    if (v is num) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  /// 人类可读的大小。
  String get sizeText {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
