import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 加载用户保存的后端地址
  await AppConfig.load();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const XkApp());
}

class XkApp extends StatelessWidget {
  const XkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xk的工作台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF185FA5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(),
    );
  }
}
