import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';
import 'core/theme/scrapyard_theme.dart';
import 'core/router/app_router.dart';
import 'features/onboarding/presentation/widgets/smelt_guide_overlay.dart';
import 'features/splash/presentation/widgets/splash_gate.dart';

void _reportError(Object error, StackTrace stack, {String? context}) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'scrapyard',
      context: context == null ? null : ErrorDescription(context),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    _reportError(error, stack, context: 'platform dispatcher');
    // false = let the engine's default handler also see it (Play vitals / logcat).
    return false;
  };
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runZonedGuarded(
    () {
      runApp(
        const ProviderScope(
          child: ScrapyardApp(),
        ),
      );
    },
    (error, stack) {
      _reportError(error, stack, context: 'uncaught zone');
    },
  );
}

class ScrapyardApp extends StatelessWidget {
  const ScrapyardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Scrapyard',
      theme: ScrapTheme.themeData,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => SplashGate(
        child: Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            const SmeltGuideOverlay(),
          ],
        ),
      ),
    );
  }
}
