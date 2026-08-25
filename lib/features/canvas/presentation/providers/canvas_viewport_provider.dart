import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ink_renderer.dart';
import '../../domain/models/canvas_viewport.dart';
import '../../domain/models/stroke.dart';
import '../../domain/services/stroke_spatial_index.dart';
import 'canvas_providers.dart';

/// Spatial index rebuilt whenever the stroke list identity changes.
final strokeSpatialIndexProvider = Provider<StrokeSpatialIndex>((ref) {
  final strokes = ref.watch(strokesProvider);
  final index = StrokeSpatialIndex();
  index.rebuild(strokes);
  return index;
});

final canvasViewportProvider =
    StateNotifierProvider<CanvasViewportNotifier, CanvasViewport>((ref) {
  return CanvasViewportNotifier(ref);
});

class CanvasViewportNotifier extends StateNotifier<CanvasViewport> {
  CanvasViewportNotifier(this._ref) : super(const CanvasViewport()) {
    _ref.listen<String>(activeNoteIdProvider, (prev, next) {
      if (prev != next) _loadForNote(next);
    });
    _ref.listen<PageCanvasConfig>(pageLayoutProvider, (prev, next) {
      if (next.isInfinite && prev?.isInfinite != true) {
        _onEnteredInfinite();
      }
    });
    _loadForNote(_ref.read(activeNoteIdProvider));
  }

  final Ref _ref;
  Offset? _home;
  Rect? _contentBounds;
  Size _viewportSize = Size.zero;
  Timer? _persistViewTimer;
  String? _noteId;

  Offset get homeAnchor => _home ?? Offset.zero;

  bool get hasHome => _home != null;

  Size get viewportSize => _viewportSize;

  void setViewportSize(Size size) {
    if (size.isEmpty) return;
    if (size == _viewportSize) return;
    final old = _viewportSize;
    _viewportSize = size;
    // Keep the same world-width in view when the editor is squished (Ask
    // opening) or restored, instead of cropping the right of the paper.
    if (old.width > 1 && (size.width - old.width).abs() > 0.5) {
      final factor = size.width / old.width;
      final newScale = (state.scale * factor).clamp(
        CanvasViewport.minScaleInfinite,
        CanvasViewport.maxScaleInfinite,
      );
      state = _clamp(CanvasViewport(pan: state.pan, scale: newScale));
    } else {
      state = _clamp(state);
    }
  }

  Future<void> _loadForNote(String noteId) async {
    _noteId = noteId;
    _home = null;
    _contentBounds = null;
    state = const CanvasViewport();

    final repo = _ref.read(canvasSettingsRepositoryProvider);
    final saved = await repo.loadNoteSettings(noteId);
    if (_noteId != noteId) return;

    if (saved != null) {
      if (saved.hasHome) {
        _home = Offset(saved.homeX!, saved.homeY!);
      }
      if (saved.viewX != null &&
          saved.viewY != null &&
          saved.viewScale != null) {
        state = CanvasViewport(
          pan: Offset(saved.viewX!, saved.viewY!),
          scale: saved.viewScale!,
        );
      }
    }

    _rebuildContentBounds();
    if (_home == null) {
      _home = _inferHomeFromStrokes();
    }
    state = _clamp(state);
  }

  void _onEnteredInfinite() {
    _rebuildContentBounds();
    if (_home == null) {
      _home = _inferHomeFromStrokes();
    }
    // On conversion, frame the existing sheet content if we have any.
    if (_contentBounds != null && _viewportSize.isEmpty == false) {
      // Keep current zoom; just ensure pan is valid.
      state = _clamp(state);
    }
  }

  void _rebuildContentBounds() {
    final strokes = _ref.read(strokesProvider);
    Rect? union;
    for (final s in strokes) {
      if (s.isHidden || s.points.isEmpty) continue;
      final b = InkRenderer.boundsOf(s.points, pad: s.baseWidth);
      union = union == null ? b : union.expandToInclude(b);
    }
    _contentBounds = union;
  }

  Offset? _inferHomeFromStrokes() {
    final strokes = _ref.read(strokesProvider);
    for (final s in strokes) {
      if (s.isHidden || s.points.isEmpty) continue;
      final b = InkRenderer.boundsOf(s.points, pad: s.baseWidth);
      return b.center;
    }
    return null;
  }

  /// Call after a stroke is committed so pan bounds and home update.
  void onStrokeCommitted(Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final b = InkRenderer.boundsOf(stroke.points, pad: stroke.baseWidth);
    _contentBounds =
        _contentBounds == null ? b : _contentBounds!.expandToInclude(b);

    if (_home == null &&
        _ref.read(pageLayoutProvider).isInfinite) {
      _home = b.center;
      _persistHome();
    }
    state = _clamp(state);
  }

  void onStrokesChanged() {
    _rebuildContentBounds();
    state = _clamp(state);
  }

  void panByScreenDelta(Offset screenDelta) {
    final worldDelta = screenDelta / state.scale;
    // Dragging content right means decreasing pan (world under origin moves left).
    state = _clamp(state.copyWith(pan: state.pan - worldDelta));
    _schedulePersistView();
  }

  void setScaleAround(double newScale, Offset screenFocal) {
    final clamped = newScale.clamp(
      CanvasViewport.minScaleInfinite,
      CanvasViewport.maxScaleInfinite,
    );
    final worldFocal = state.toWorld(screenFocal);
    final newPan = Offset(
      worldFocal.dx - screenFocal.dx / clamped,
      worldFocal.dy - screenFocal.dy / clamped,
    );
    state = _clamp(CanvasViewport(pan: newPan, scale: clamped));
    _schedulePersistView();
  }

  void setViewport(CanvasViewport next) {
    state = _clamp(next);
    _schedulePersistView();
  }

  /// Animate (or snap) so [homeAnchor] is centered in the viewport.
  void goHome({Size? viewportSize}) {
    final size = viewportSize ?? _viewportSize;
    if (size.isEmpty) return;
    final home = _home ?? Offset.zero;
    final scale = state.scale;
    final pan = Offset(
      home.dx - size.width / (2 * scale),
      home.dy - size.height / (2 * scale),
    );
    state = _clamp(CanvasViewport(pan: pan, scale: scale));
    _schedulePersistView();
  }

  CanvasViewport _clamp(CanvasViewport vp) {
    final size = _viewportSize;
    if (size.isEmpty) return vp;

    final scale = vp.scale.clamp(
      CanvasViewport.minScaleInfinite,
      CanvasViewport.maxScaleInfinite,
    );

    // Allow panning within content bounds inflated by 1.5 viewports,
    // floored at a default sheet so empty canvases still feel bounded.
    final viewW = size.width / scale;
    final viewH = size.height / scale;
    final pad = Offset(viewW * 1.5, viewH * 1.5);

    final floor = Rect.fromLTWH(
      -viewW * 0.5,
      -viewH * 0.5,
      math.max(size.width, viewW) + viewW,
      math.max(5000.0, viewH) + viewH,
    );

    final content = (_contentBounds ?? floor).inflate(0).expandToInclude(floor);
    final allowed = Rect.fromLTRB(
      content.left - pad.dx,
      content.top - pad.dy,
      content.right + pad.dx,
      content.bottom + pad.dy,
    );

    // Pan is the world point at screen origin; visible world is
    // [pan, pan + viewSize]. Keep that rect intersecting [allowed].
    final minPanX = allowed.left;
    final maxPanX = allowed.right - viewW;
    final minPanY = allowed.top;
    final maxPanY = allowed.bottom - viewH;

    final panX = maxPanX < minPanX
        ? (allowed.left + allowed.right - viewW) / 2
        : vp.pan.dx.clamp(minPanX, maxPanX);
    final panY = maxPanY < minPanY
        ? (allowed.top + allowed.bottom - viewH) / 2
        : vp.pan.dy.clamp(minPanY, maxPanY);

    return CanvasViewport(pan: Offset(panX, panY), scale: scale);
  }

  void _schedulePersistView() {
    _persistViewTimer?.cancel();
    _persistViewTimer = Timer(const Duration(milliseconds: 400), _persistView);
  }

  Future<void> _persistView() async {
    final noteId = _ref.read(activeNoteIdProvider);
    if (_ref.read(ephemeralNoteIdsProvider).contains(noteId)) return;
    if (!_ref.read(pageLayoutProvider).isInfinite) return;
    await _ref.read(canvasSettingsRepositoryProvider).upsertView(
          noteId,
          x: state.pan.dx,
          y: state.pan.dy,
          scale: state.scale,
        );
  }

  Future<void> _persistHome() async {
    final home = _home;
    if (home == null) return;
    final noteId = _ref.read(activeNoteIdProvider);
    if (_ref.read(ephemeralNoteIdsProvider).contains(noteId)) return;
    await _ref
        .read(canvasSettingsRepositoryProvider)
        .upsertHome(noteId, home.dx, home.dy);
  }

  @override
  void dispose() {
    _persistViewTimer?.cancel();
    super.dispose();
  }
}
