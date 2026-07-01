import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/canvas/presentation/screens/note_editor_screen.dart';
import '../../features/pdf_viewer/presentation/screens/pdf_viewer_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/gestures/presentation/screens/gesture_settings_screen.dart';
import '../../features/memory/presentation/screens/memory_settings_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/note_editor',
        name: 'note_editor',
        builder: (context, state) => const NoteEditorScreen(),
      ),
      GoRoute(
        path: '/pdf_viewer',
        name: 'pdf_viewer',
        builder: (context, state) => const PdfViewerScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
           GoRoute(
             path: 'gestures',
             name: 'gesture_settings',
             builder: (context, state) => const GestureSettingsScreen(),
           ),
           GoRoute(
             path: 'memory',
             name: 'memory_settings',
             builder: (context, state) => const MemorySettingsScreen(),
           ),
        ]
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
    ],
  );
}
