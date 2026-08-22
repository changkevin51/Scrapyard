import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../theme/scrap_motion.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/canvas/presentation/screens/note_editor_screen.dart';
import '../../features/pdf_viewer/presentation/screens/pdf_viewer_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/gestures/presentation/screens/gesture_settings_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/guide/presentation/screens/guide_screen.dart';
import '../../features/guide/presentation/screens/guide_topic_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// Slight upward slide — like pulling a sheet off a pile.
/// Slide-only (no FadeTransition) so Impeller never allocates a huge
/// offscreen texture for the 5000px note canvas.
CustomTransitionPage<void> _scrapPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: ScrapMotion.route,
    reverseTransitionDuration: ScrapMotion.route,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Incoming sheet lifts from the pile.
      final enter = Tween<Offset>(
        begin: const Offset(0, 0.05),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: ScrapMotion.routeCurve,
      ));
      // Covered page drifts up a hair under the new sheet.
      final covered = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(0, -0.025),
      ).animate(CurvedAnimation(
        parent: secondaryAnimation,
        curve: ScrapMotion.routeCurve,
      ));
      return SlideTransition(
        position: covered,
        child: SlideTransition(
          position: enter,
          child: child,
        ),
      );
    },
  );
}

class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        pageBuilder: (context, state) => _scrapPage(
          key: state.pageKey,
          child: const HomeScreen(),
        ),
      ),
      GoRoute(
        path: '/note_editor',
        name: 'note_editor',
        pageBuilder: (context, state) => _scrapPage(
          key: state.pageKey,
          child: const NoteEditorScreen(),
        ),
      ),
      GoRoute(
        path: '/pdf_viewer',
        name: 'pdf_viewer',
        pageBuilder: (context, state) => _scrapPage(
          key: state.pageKey,
          child: const PdfViewerScreen(),
        ),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) => _scrapPage(
          key: state.pageKey,
          child: const SettingsScreen(),
        ),
        routes: [
          GoRoute(
            path: 'gestures',
            name: 'gesture_settings',
            pageBuilder: (context, state) => _scrapPage(
              key: state.pageKey,
              child: const GestureSettingsScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/guide',
        name: 'guide',
        pageBuilder: (context, state) => _scrapPage(
          key: state.pageKey,
          child: const GuideScreen(),
        ),
        routes: [
          GoRoute(
            path: ':topic',
            name: 'guide_topic',
            pageBuilder: (context, state) => _scrapPage(
              key: state.pageKey,
              child: GuideTopicScreen(
                topicId: state.pathParameters['topic'] ?? '',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) => _scrapPage(
          key: state.pageKey,
          child: OnboardingScreen(
            replayGuide: state.uri.queryParameters['replay'] == '1',
          ),
        ),
      ),
    ],
  );
}
