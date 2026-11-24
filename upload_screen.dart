import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../providers/file_repository.dart';

/// 上传页：选文件 → 显示进度 → 完成后返回。
/// 选中的文件会标"来源=手机、分类=速传"，上传后自动出现在电脑端「手机上传」页。
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _repo = FileRepository();

  String? _fileName;
  int? _fileSize;
  Uint8List? _bytes;
  double _progress = 0;
  bool _uploading = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true, // 选择时一次性拿到字节，避免二次弹窗
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    setState(() {
      _fileName = picked.name;
      _fileSize = picked.size;
      _bytes = picked.bytes;
      _error = null;
      _done = null;
      _progress = 0;
    });
  }

  Future<void> _upload() async {
    if (_fileName == null || _bytes == null) {
      setState(() => _error = '请先选择文件。');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
      _progress = 0;
    });
    try {
      await _repo.upload(
        name: _fileName!,
        bytes: _bytes!,
        mime: _guessMime(_fileName!),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _done = '上传成功';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = '上传失败：$e';
      });
    }
  }

  String _guessMime(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    const map = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'json': 'application/json',
      'zip': 'application/zip',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  String _sizeText(int? n) {
    if (n == null) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('上传文件')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.insert_drive_file),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fileName ?? '尚未选择文件',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (_fileSize != null)
                          Text(
                            _sizeText(_fileSize),
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: _uploading ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: Text(_fileName == null ? '选择文件' : '重新选择'),
            ),
            const SizedBox(height: 24),

            if (_uploading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                '上传中 ${(_progress * 100).round()}%',
                textAlign: TextAlign.center,
              ),
            ],

            if (_done != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_done，电脑端「手机上传」2 秒内可见',
                        style: TextStyle(color: Colors.green.shade800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('完成'),
              ),
            ] else if (_fileName != null && !_uploading) ...[
              FilledButton.icon(
                onPressed: _upload,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('开始上传'),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],

            const Spacer(),
            Text(
              '大文件也支持（上限 2GB），上传会显示进度。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
