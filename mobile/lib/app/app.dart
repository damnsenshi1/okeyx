import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class OkeyXApp extends StatelessWidget {
  const OkeyXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'OkeyX',
      theme: AppTheme.darkTheme,

      routerConfig: appRouter,
    );
  }
}