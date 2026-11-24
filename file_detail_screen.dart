import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/file_item.dart';
import '../providers/file_repository.dart';

/// 文件详情页：访问预览 / 下载到手机 / 删除（两端同步）。
class FileDetailScreen extends StatefulWidget {
  final FileItem file;
  const FileDetailScreen({super.key, required this.file});

  @override
  State<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends State<FileDetailScreen> {
  final _repo = FileRepository();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  /// 下载并用系统应用打开（访问/预览）。
  Future<void> _open() async {
    setState(() {
      _busy = true;
      _msg = '正在下载…';
    });
    try {
      final bytes = await _repo.download(widget.file);
      final path = await _saveToTemp(widget.file.name, bytes);
      final result = await OpenFilex.open(path);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = result.type == ResultType.noAppToOpen
            ? '没有能打开此文件的应用，可先「下载到手机」。'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = '打开失败：$e';
      });
    }
  }

  /// 下载到手机的下载目录。
  Future<void> _download() async {
    setState(() {
      _busy = true;
      _msg = '正在下载…';
    });
    try {
      final bytes = await _repo.download(widget.file);
      Directory dir;
      try {
        dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      } catch (_) {
        dir = await getTemporaryDirectory();
      }
      final safeName = widget.file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = '${dir.path}${Platform.pathSeparator}$safeName';
      final f = File(path);
      // 同名时加序号，避免覆盖
      var finalPath = path;
      var i = 1;
      while (await f.exists()) {
        final dot = safeName.lastIndexOf('.');
        final base = dot > 0 ? safeName.substring(0, dot) : safeName;
        final ext = dot > 0 ? safeName.substring(dot) : '';
        finalPath = '${dir.path}${Platform.pathSeparator}$base($i)$ext';
        i++;
      }
      await File(finalPath).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = '已保存到：$finalPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = '下载失败：$e';
      });
    }
  }

  Future<String> _saveToTemp(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${dir.path}${Platform.pathSeparator}$safeName';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// 删除：二次确认 → 只删元数据+墓碑+回收站，保留内容 7 天可恢复。
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除？'),
        content: const Text(
          '删除后，这个文件会从手机和电脑两端同时消失。\n'
          '内容会保留在「最近删除」7 天，期间可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _repo.delete(widget.file);
      if (!mounted) return;
      Navigator.of(context).pop(true); // 返回并刷新列表
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = '删除失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    return Scaffold(
      appBar: AppBar(title: const Text('文件详情')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.description, size: 56, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                f.name,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                '${f.sizeText} · ${f.isFromMobile ? '手机上传' : '电脑上传'}'
                '${f.updatedAt.isNotEmpty ? ' · ${f.updatedAt.substring(0, 16).replaceFirst("T", " ")}' : ''}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),

              FilledButton.icon(
                onPressed: _busy ? null : _open,
                icon: const Icon(Icons.visibility),
                label: const Text('访问 / 打开预览'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download),
                label: const Text('下载到手机'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除（两端同步）'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),

              if (_msg != null) ...[
                const SizedBox(height: 20),
                Text(
                  _msg!,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ],
          ),
          if (_busy)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
