import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../providers/file_repository.dart';
import 'file_detail_screen.dart';
import 'upload_screen.dart';

/// 文件首页：分类列表 + 2 秒轮询自动同步 + 上传入口。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = FileRepository();

  List<FileItem> _all = [];
  int _filter = 0; // 0=全部 1=手机上传 2=电脑上传
  bool _loading = true;
  String? _error;
  int _lastStamp = -1;
  int _pollTick = 0;

  @override
  void initState() {
    super.initState();
    // 启动先补传上次断网时暂存的操作，再拉列表
    _startup();
    // 每 2 秒问一次后端"变了没"，变了才重新拉列表（省流量、秒级同步）
    Future.delayed(const Duration(seconds: 2), _poll);
  }

  Future<void> _startup() async {
    try {
      final n = await _repo.initAndDrain();
      if (n > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已联网，补传了 $n 条离线操作')),
        );
      }
    } catch (_) {}
    await _refresh(silent: true);
  }

  Future<void> _poll() async {
    if (!mounted) return;
    try {
      // 每 5 轮（约 10 秒）尝试补传一次离线队列
      _pollTick++;
      if (_pollTick % 5 == 0) {
        final n = await _repo.drainPending();
        if (n > 0) await _refresh(silent: true);
      }
      final stamp = await _repo.fileLatest();
      if (stamp != _lastStamp && _lastStamp != -1) {
        await _refresh(silent: true);
      }
      _lastStamp = stamp;
    } catch (_) {
      // 轮询失败不影响当前列表
    }
    if (mounted) {
      Future.delayed(const Duration(seconds: 2), _poll);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final files = await _repo.loadFiles();
      if (!mounted) return;
      setState(() {
        _all = files;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '连接失败：${e.toString()}';
        _loading = false;
      });
    }
  }

  List<FileItem> get _visible {
    if (_filter == 1) return _all.where((f) => f.isFromMobile).toList();
    if (_filter == 2) return _all.where((f) => !f.isFromMobile).toList();
    return _all;
  }

  Future<void> _openUpload() async {
    final uploaded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UploadScreen()),
    );
    if (uploaded == true && mounted) {
      await _refresh(silent: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已上传云端，另一设备联网后自动可见（无需同时在线）')),
      );
    }
  }

  Future<void> _openDetail(FileItem f) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FileDetailScreen(file: f)),
    );
    if (changed == true && mounted) _refresh(silent: true);
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的文件'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () => _refresh(),
            ),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: '全部'),
              Tab(text: '手机上传'),
              Tab(text: '电脑上传'),
            ],
            onTap: (i) => setState(() => _filter = i),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openUpload,
          icon: const Icon(Icons.upload_file),
          label: const Text('上传文件'),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final list = _visible;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _filter == 1 ? '还没有手机上传的文件' : '这里还没有文件',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Text(
              '点右下角「上传文件」试试',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 90, top: 8),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _fileTile(list[i]),
      ),
    );
  }

  Widget _fileTile(FileItem f) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _iconColor(f.mime).withOpacity(0.12),
        child: Icon(_iconFor(f.mime), color: _iconColor(f.mime)),
      ),
      title: Text(
        f.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${f.sizeText} · ${f.isFromMobile ? '手机上传' : '电脑上传'}'
        '${f.updatedAt.isNotEmpty ? ' · ${f.updatedAt.substring(0, 10)}' : ''}',
      ),
      onTap: () => _openDetail(f),
    );
  }

  IconData _iconFor(String mime) {
    if (mime.startsWith('image/')) return Icons.image;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('document')) return Icons.description;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart;
    if (mime.startsWith('video/')) return Icons.video_file;
    return Icons.insert_drive_file;
  }

  Color _iconColor(String mime) {
    if (mime.startsWith('image/')) return Colors.purple;
    if (mime.contains('pdf')) return Colors.red;
    if (mime.contains('word') || mime.contains('document')) return Colors.blue;
    if (mime.contains('sheet') || mime.contains('excel')) return Colors.green;
    return Colors.grey.shade700;
  }
}
