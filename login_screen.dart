import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import 'home_screen.dart';

/// 登录页：先确认后端地址 → 输入访问密码 → 进入文件首页。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pwdController = TextEditingController();
  final _urlController = TextEditingController(text: AppConfig.baseUrl);
  final _api = ApiClient();

  bool _busy = false;
  bool _obscure = true;
  String? _error;
  bool _showSettings = false;

  @override
  void dispose() {
    _pwdController.dispose();
    _urlController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await AppConfig.save(_urlController.text);
    final ok = await _api.pingServer();
    setState(() {
      _busy = false;
      if (ok) {
        _showSettings = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接成功')),
        );
      } else {
        _error = '连不上云端。请确认：\n① 手机能上网（流量/WiFi 均可）\n'
            '② 地址是云端 https 地址，不带端口号\n'
            '③ 可点下方「恢复默认云端地址」重试';
      }
    });
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final online = await _api.pingServer();
    if (!online) {
      setState(() {
        _busy = false;
        _showSettings = true;
        _error = '连不上云端，请检查网络或点「恢复默认云端地址」。';
      });
      return;
    }

    final pwd = _pwdController.text.trim();
    final ok = await _api.checkPassword(pwd);
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = '密码不对，请重试（默认 123456）。');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.folder_shared_rounded,
                      size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'xk的工作台',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '手机与电脑，文件互通',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 32),

                  TextField(
                    controller: _pwdController,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _busy ? null : _login(),
                    decoration: InputDecoration(
                      labelText: '访问密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('进入工作台'),
                    ),
                  ),
                  const SizedBox(height: 8),

                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showSettings = !_showSettings),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('云端地址设置（一般不用改）'),
                  ),

                  if (_showSettings) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '数据存云端，手机和电脑不用同时在线、不用同一 WiFi。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '云端地址',
                        hintText: 'https://…app.workbuddy.host',
                        prefixIcon: Icon(Icons.cloud_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _busy ? null : _testConnection,
                          child: const Text('测试连接'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await AppConfig.resetToCloud();
                                  setState(() =>
                                      _urlController.text = AppConfig.baseUrl);
                                },
                          child: const Text('恢复默认云端地址'),
                        ),
                      ],
                    ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style:
                                  TextStyle(color: Colors.red.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
