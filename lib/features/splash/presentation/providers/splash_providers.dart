import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Flipped true when the splash overlay finishes exiting and the app is visible.
final appReadyProvider = StateProvider<bool>((ref) => false);
