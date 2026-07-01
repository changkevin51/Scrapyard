import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';

// ─────────────────────────────────────────────────────────────────
// Canvas Sticker model — an emoji/decorative sticker placed on canvas
// ─────────────────────────────────────────────────────────────────
class CanvasSticker {
  final String id;
  final Offset position;
  final String content;  // emoji or glyph
  final double size;
  final double rotation; // radians

  const CanvasSticker({
    required this.id,
    required this.position,
    required this.content,
    this.size = 48,
    this.rotation = 0,
  });

  CanvasSticker copyWith({Offset? position, double? size, double? rotation}) =>
      CanvasSticker(
        id: id, content: content,
        position: position  ?? this.position,
        size:     size      ?? this.size,
        rotation: rotation  ?? this.rotation,
      );
}

final canvasStickersProvider = StateProvider<List<CanvasSticker>>((ref) => []);

// ─────────────────────────────────────────────────────────────────
// Sticker categories
// ─────────────────────────────────────────────────────────────────
const _stickerLibrary = <({String category, List<String> items})>[
  (
    category: 'Stars & Shapes',
    items: ['⭐', '✨', '💫', '🌟', '⚡', '🔥', '❄', '🌊', '🌀', '◈', '◉', '◎', '⬡', '⬢'],
  ),
  (
    category: 'Nature',
    items: ['🌸', '🌺', '🌻', '🍀', '🌿', '🍃', '🌙', '☀', '🌈', '🍁', '🌾', '🎋', '🎍', '🌳'],
  ),
  (
    category: 'Symbols',
    items: ['✅', '❌', '⚠', '❗', '❓', '💡', '🔑', '🏷', '📌', '📍', '🎯', '🔖', '💬', '📎'],
  ),
  (
    category: 'Mood',
    items: ['😊', '🤔', '💭', '💡', '🎉', '👍', '❤', '💯', '🚀', '🎯', '✊', '🙏', '👀', '🫀'],
  ),
  (
    category: 'Study',
    items: ['📚', '📝', '✏', '📐', '🔬', '🧪', '⏰', '📅', '🗂', '📊', '📈', '🖊', '📖', '🗒'],
  ),
  (
    category: 'Japanese',
    items: ['⛩', '🏯', '🗾', '🎎', '🎏', '🎐', '🎑', '🀄', '🎴', '🏮', '🎋', '🎍', '⛸', '🍱'],
  ),
];

// ─────────────────────────────────────────────────────────────────
// Sticker Library Panel
// ─────────────────────────────────────────────────────────────────
class StickerLibraryPanel extends ConsumerStatefulWidget {
  final Offset? tapPosition; // where to place the sticker

  const StickerLibraryPanel({super.key, this.tapPosition});

  @override
  ConsumerState<StickerLibraryPanel> createState() => _StickerLibraryPanelState();
}

class _StickerLibraryPanelState extends ConsumerState<StickerLibraryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  int _selectedCategory = 0;
  String? _hovered;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _stickerLibrary.length, vsync: this);
    _tabCtrl.addListener(() => setState(() => _selectedCategory = _tabCtrl.index));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _place(String emoji) {
    final sticker = CanvasSticker(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: widget.tapPosition ?? const Offset(100, 200),
      content: emoji,
      size: 48,
    );
    ref.read(canvasStickersProvider.notifier).update((s) => [...s, sticker]);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cat = _stickerLibrary[_selectedCategory];

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: KotoTheme.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: KotoTheme.dividers,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text('Stickers', style: KotoTextStyles.heading.copyWith(fontSize: 18)),
                const Spacer(),
                Text('Tap to place', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Category tabs (scrollable, pill style)
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _stickerLibrary.length,
              itemBuilder: (ctx, i) {
                final isActive = i == _selectedCategory;
                return GestureDetector(
                  onTap: () {
                    _tabCtrl.animateTo(i);
                    setState(() => _selectedCategory = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive ? KotoTheme.accent : KotoTheme.background,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isActive ? KotoTheme.accent : KotoTheme.dividers,
                      ),
                    ),
                    child: Text(
                      _stickerLibrary[i].category,
                      style: KotoTextStyles.caption.copyWith(
                        fontSize: 11,
                        color: isActive ? Colors.white : KotoTheme.secondaryText,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: KotoTheme.dividers, height: 1),
          // Sticker grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: cat.items.length,
              itemBuilder: (ctx, i) {
                final emoji = cat.items[i];
                final isHov = _hovered == emoji;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hovered = emoji),
                  onExit:  (_) => setState(() => _hovered = null),
                  child: GestureDetector(
                    onTap: () => _place(emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      decoration: BoxDecoration(
                        color: isHov
                            ? KotoTheme.accent.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(emoji,
                            style: TextStyle(fontSize: isHov ? 32 : 28)),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

void showStickerLibrary(BuildContext context, {Offset? tapPosition}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StickerLibraryPanel(tapPosition: tapPosition),
  );
}

// ─────────────────────────────────────────────────────────────────
// Sticker overlay widget — draggable, resizable, rotatable, deletable
// ─────────────────────────────────────────────────────────────────
class CanvasStickerOverlay extends ConsumerStatefulWidget {
  final CanvasSticker sticker;

  const CanvasStickerOverlay({super.key, required this.sticker});

  @override
  ConsumerState<CanvasStickerOverlay> createState() => _CanvasStickerOverlayState();
}

class _CanvasStickerOverlayState extends ConsumerState<CanvasStickerOverlay> {
  bool _selected = false;
  late double _size;
  late double _rotation;

  @override
  void initState() {
    super.initState();
    _size     = widget.sticker.size;
    _rotation = widget.sticker.rotation;
  }

  void _update({Offset? position, double? size, double? rotation}) {
    final stickers = ref.read(canvasStickersProvider);
    final idx = stickers.indexWhere((s) => s.id == widget.sticker.id);
    if (idx < 0) return;
    final updated = stickers[idx].copyWith(
      position: position,
      size:     size,
      rotation: rotation,
    );
    final newList = List<CanvasSticker>.from(stickers);
    newList[idx] = updated;
    ref.read(canvasStickersProvider.notifier).state = newList;
  }

  void _delete() {
    ref.read(canvasStickersProvider.notifier)
        .update((s) => s.where((x) => x.id != widget.sticker.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.sticker.position.dx - _size / 2,
      top:  widget.sticker.position.dy - _size / 2,
      child: GestureDetector(
        onTap: () => setState(() => _selected = !_selected),
        onPanUpdate: (d) => _update(
          position: widget.sticker.position + d.delta,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The sticker itself — pure emoji, no background
            Transform.rotate(
              angle: _rotation,
              child: Text(
                widget.sticker.content,
                style: TextStyle(
                  fontSize: _size,
                  decoration: TextDecoration.none,
                  // No background — transparent
                ),
              ),
            ),

            // Selection ring + handles (only when selected)
            if (_selected) ...[
              // Dashed selection border
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: KotoTheme.accent.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // Delete — top right
              Positioned(
                top: -14, right: -14,
                child: GestureDetector(
                  onTap: _delete,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: KotoTheme.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: KotoTheme.dividers),
                      boxShadow: KotoTheme.subtleShadow,
                    ),
                    child: const Icon(Icons.close, size: 14,
                        color: KotoTheme.secondaryText),
                  ),
                ),
              ),

              // Resize — bottom right
              Positioned(
                bottom: -14, right: -14,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    setState(() => _size = (_size + d.delta.dx).clamp(20.0, 140.0));
                    _update(size: _size);
                  },
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: KotoTheme.accent,
                      shape: BoxShape.circle,
                      boxShadow: KotoTheme.subtleShadow,
                    ),
                    child: const Icon(Icons.open_in_full, size: 12, color: Colors.white),
                  ),
                ),
              ),

              // Rotate — bottom left
              Positioned(
                bottom: -14, left: -14,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    setState(() => _rotation += d.delta.dx * 0.03);
                    _update(rotation: _rotation);
                  },
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: KotoTheme.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: KotoTheme.accent),
                      boxShadow: KotoTheme.subtleShadow,
                    ),
                    child: const Icon(Icons.rotate_right, size: 12,
                        color: KotoTheme.accent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
