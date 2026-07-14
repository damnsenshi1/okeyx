import 'package:flutter/material.dart';
import '../features/auth/presentation/pages/login_page.dart';

class OkeyXApp extends StatelessWidget {
  const OkeyXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OkeyX',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const LoginPage(),
    );
  }
}