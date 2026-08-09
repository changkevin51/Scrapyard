import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';

/// Shared paper-chit shell for selection / smelt / paste menus.
class PaperChit extends StatelessWidget {
  final Widget child;

  const PaperChit({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1.0),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
      child: Transform.rotate(
        angle: -0.8 * math.pi / 180,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: ScrapTheme.cardSurface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: ScrapTheme.kraft.withValues(alpha: 0.75),
                width: 0.85,
              ),
              boxShadow: ScrapTheme.deskShadow,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class MenuPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const MenuPressable({super.key, required this.child, required this.onTap});

  @override
  State<MenuPressable> createState() => _MenuPressableState();
}

class _MenuPressableState extends State<MenuPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        ScrapFeedback.tap();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: ScrapMotion.press,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          _pressed ? 1.5 : 0.0,
          _pressed ? 1.5 : 0.0,
          0,
        ),
        transformAlignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

/// Compact stamp-style chip for floating selection menus.
enum PaperMenuChipTone { primary, secondary, ghost, danger }

class PaperMenuChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final PaperMenuChipTone tone;

  const PaperMenuChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone = PaperMenuChipTone.secondary,
  });

  Color get _fill => switch (tone) {
        PaperMenuChipTone.primary => ScrapTheme.accentSurface,
        PaperMenuChipTone.secondary => ScrapTheme.codeSurface,
        PaperMenuChipTone.ghost => Colors.transparent,
        PaperMenuChipTone.danger => ScrapTheme.inkRed.withValues(alpha: 0.08),
      };

  Color get _border => switch (tone) {
        PaperMenuChipTone.primary => ScrapTheme.accent.withValues(alpha: 0.45),
        PaperMenuChipTone.secondary => ScrapTheme.dividers,
        PaperMenuChipTone.ghost => ScrapTheme.dividers,
        PaperMenuChipTone.danger => ScrapTheme.inkRed.withValues(alpha: 0.4),
      };

  Color get _ink => switch (tone) {
        PaperMenuChipTone.primary => ScrapTheme.accent,
        PaperMenuChipTone.secondary => ScrapTheme.primaryText,
        PaperMenuChipTone.ghost => ScrapTheme.secondaryText,
        PaperMenuChipTone.danger => ScrapTheme.inkRed,
      };

  @override
  Widget build(BuildContext context) {
    return MenuPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _fill,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: _border, width: 1),
          boxShadow:
              tone == PaperMenuChipTone.ghost ? const [] : ScrapTheme.deskShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: _ink),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: ScrapTextStyles.stamp.copyWith(
                color: _ink,
                fontSize: 10,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SmeltPillButton extends StatelessWidget {
  final VoidCallback onTap;

  const SmeltPillButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PaperMenuChip(
      label: '⟨ Smelt ⟩',
      onTap: onTap,
      tone: PaperMenuChipTone.primary,
    );
  }
}

class SmeltCodePillButton extends StatelessWidget {
  final VoidCallback onTap;

  const SmeltCodePillButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperMenuChip(
          label: 'Smelt + code',
          icon: Icons.code,
          onTap: onTap,
          tone: PaperMenuChipTone.secondary,
        ),
        const Positioned(
          top: -7,
          right: -5,
          child: PaperNewSticker(),
        ),
      ],
    );
  }
}

class PaperNewSticker extends StatelessWidget {
  const PaperNewSticker({super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 9 * math.pi / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: ScrapTheme.tape,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: ScrapTheme.kraft.withValues(alpha: 0.75),
            width: 0.75,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              offset: Offset(1, 1),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          'NEW',
          style: ScrapTextStyles.stamp.copyWith(
            color: ScrapTheme.accent,
            fontSize: 7,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }
}

class AddToChatButton extends StatelessWidget {
  final VoidCallback onTap;

  const AddToChatButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PaperMenuChip(
      label: 'Add to chat',
      icon: Icons.chat_bubble_outline,
      onTap: onTap,
      tone: PaperMenuChipTone.ghost,
    );
  }
}

class ManualSelectButton extends StatelessWidget {
  final VoidCallback onTap;

  const ManualSelectButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PaperMenuChip(
      label: 'Select manually',
      onTap: onTap,
      tone: PaperMenuChipTone.ghost,
    );
  }
}

/// Scrap Smelt action menu — same chips used on the note canvas.
///
/// When [rect] is set, wraps in [Positioned] above the selection (canvas).
/// When null, returns the bare chit (e.g. PDF [Overlay]).
class SmeltActionMenu extends StatelessWidget {
  final Rect? rect;
  final VoidCallback onSmelt;
  final VoidCallback onSmeltWithCode;
  final VoidCallback? onAddToChat;
  final VoidCallback? onManualSelect;
  final bool showManualSelect;

  const SmeltActionMenu({
    super.key,
    this.rect,
    required this.onSmelt,
    required this.onSmeltWithCode,
    this.onAddToChat,
    this.onManualSelect,
    this.showManualSelect = false,
  });

  @override
  Widget build(BuildContext context) {
    final chit = PaperChit(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmeltPillButton(onTap: onSmelt),
          const SizedBox(width: 8),
          SmeltCodePillButton(onTap: onSmeltWithCode),
          if (onAddToChat != null) ...[
            const SizedBox(width: 8),
            AddToChatButton(onTap: onAddToChat!),
          ],
          if (showManualSelect && onManualSelect != null) ...[
            const SizedBox(width: 8),
            ManualSelectButton(onTap: onManualSelect!),
          ],
        ],
      ),
    );

    final r = rect;
    if (r == null) return chit;

    final top = math.max(r.top - 64, 12.0);
    final left = math.max(r.left, 12.0);
    return Positioned(top: top, left: left, child: chit);
  }
}
