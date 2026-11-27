import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'core/game_audio.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/api_endpoint.dart';
import 'core/config.dart';
import 'core/crash_reporter.dart';
import 'core/push_service.dart';
import 'features/auth/auth_gate.dart';
import 'features/phase4/ad_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint(
        'OKEYX_FLUTTER_ERROR: ${details.exceptionAsString()}\n${details.stack ?? StackTrace.current}',
      );
      debugPrint('OKEYX_FLUTTER_DETAILS:\n${details.toString()}');
      CrashReporter.report(details.exception, details.stack, context: details.context?.toDescription() ?? 'flutter');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('OKEYX_PLATFORM_ERROR: $error\n$stack');
      CrashReporter.report(error, stack, fatal: true, context: 'platform');
      return true;
    };
    ErrorWidget.builder = (details) {
      debugPrint(
        'OKEYX_ERROR_WIDGET: ${details.exceptionAsString()}\n${details.stack ?? StackTrace.current}',
      );
      return const Material(
        color: Color(0xFF110B30),
        child: Center(
          child: Text(
            'OkeyX ekran hatasi kaydedildi.',
            textDirection: TextDirection.ltr,
          ),
        ),
      );
    };

    await ApiEndpoint.init();
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (AppConfig.hasSupabase) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
    }
    // Arka plana atılınca lobi müziği/radyo durur, geri gelince devam eder.
    _audioLifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
        unawaited(GameAudio.pauseForBackground());
      } else if (state == AppLifecycleState.resumed) {
        unawaited(GameAudio.resumeFromBackground());
      }
    });
    runApp(const OkeyXApp());
    // Ads/WebView initialization was one of the biggest first-frame stalls on
    // low-end Android in device logs. Let the first UI frame settle first.
    Future<void>.delayed(const Duration(seconds: 7), () async {
      try {
        await AdService.initialize();
        await PushService.init();
      } catch (error, stack) {
        debugPrint('OKEYX_ADS_INIT_ERROR: $error\n$stack');
      }
    });
  }, (error, stack) {
    debugPrint('OKEYX_ZONE_ERROR: $error\n$stack');
    CrashReporter.report(error, stack, fatal: true, context: 'zone');
  });
}

// ignore: unused_element
AppLifecycleListener? _audioLifecycle;

class OkeyXApp extends StatelessWidget {
  const OkeyXApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildOkeyXTheme(),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: const TextScaler.linear(1)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const AuthGate(),
        // Supabase PKCE returns through okeyx://auth/callback. Android also
        // forwards that path to Flutter's Navigator; without a route handler
        // WidgetsApp throws even though Supabase already consumed the code.
        onGenerateRoute: (settings) {
          final name = settings.name ?? '';
          if (name == '/' || name.startsWith('/callback')) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const AuthGate(),
            );
          }
          return null;
        },
        onUnknownRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const AuthGate(),
        ),
      );
}
