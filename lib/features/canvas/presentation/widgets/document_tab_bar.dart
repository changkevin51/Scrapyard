import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Document Tab Bar
// Scrapyard-themed filing tabs — sheets rising off the desk.
//
// Design: Horizontal scrollable strip of index-card tabs.
// Active tab merges into the canvas below (no bottom border).
// Inactive tabs sit lower on a kraft/codeSurface fill.
// ─────────────────────────────────────────────────────────────────
class DocumentTabBar extends ConsumerWidget {
  const DocumentTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs     = ref.watch(openedTabsProvider);
    final activeId = ref.watch(activeTabIdProvider);
    final groups   = ref.watch(tabGroupsProvider);
    final ephemeralIds = ref.watch(ephemeralNoteIdsProvider);

    if (tabs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: ScrapTheme.background,
        border: Border(bottom: BorderSide(color: ScrapTheme.dividers, width: 0.5)),
      ),
      child: Row(
        children: [
          // Back button - navigate to home
          _BackHomeButton(
            onTap: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              itemCount: tabs.length,
              itemBuilder: (ctx, i) {
                final tab      = tabs[i];
                final isActive = tab.id == activeId;
                final isEphemeral = ephemeralIds.contains(tab.id);
                final group    = groups.firstWhereOrNull((g) => g.id == tab.groupId);
                return _TabChip(
                  tab: tab,
                  isActive: isActive,
                  isEphemeral: isEphemeral,
                  groupName: group?.name,
                  onTap: () {
                    ref.read(activeTabIdProvider.notifier).state = tab.id;
                    ref.read(activeNoteIdProvider.notifier).state = tab.id;
                  },
                  onClose: () {
                    if (isEphemeral) {
                      discardEphemeralNote(ref, tab.id);
                      return;
                    }
                    final updated = tabs.where((t) => t.id != tab.id).toList();
                    ref.read(openedTabsProvider.notifier).state = updated;
                    if (activeId == tab.id) {
                      final next = updated.isNotEmpty ? updated.last.id : null;
                      ref.read(activeTabIdProvider.notifier).state = next;
                      if (next != null) {
                        ref.read(activeNoteIdProvider.notifier).state = next;
                      }
                    }
                  },
                  onLongPress: () => _showTabMenu(ctx, ref, tab, tabs, groups),
                );
              },
            ),
          ),
          // New tab button
          GestureDetector(
            onTap: () {}, // hook from outside to open note picker
            child: Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: ScrapTheme.kraft.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ScrapTheme.dividers),
              ),
              child: const Icon(Icons.add, size: 16, color: ScrapTheme.mutedText),
            ),
          ),
        ],
      ),
    );
  }

  void _showTabMenu(
    BuildContext context,
    WidgetRef ref,
    OpenedTab tab,
    List<OpenedTab> tabs,
    List<TabGroup> groups,
  ) {
    showScrapSheet(
      context: context,
      backgroundColor: ScrapTheme.cardSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ScrapTheme.borderRadiusDefault))),
      builder: (_) => _TabMenuSheet(tab: tab, tabs: tabs, groups: groups),
    );
  }
}

// ─── Individual filing tab ───────────────────────────────────────
class _TabChip extends StatelessWidget {
  final OpenedTab tab;
  final bool isActive;
  final bool isEphemeral;
  final String? groupName;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onLongPress;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.isEphemeral,
    required this.onTap,
    required this.onClose,
    required this.onLongPress,
    this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    final borderStyle = isEphemeral
        ? Border(
            top: BorderSide(
              color: isActive
                  ? tab.accent.withValues(alpha: 0.7)
                  : ScrapTheme.dividers,
              width: isActive ? 2 : 1,
              style: BorderStyle.solid,
            ),
            left: BorderSide(
              color: ScrapTheme.dividers.withValues(alpha: 0.85),
              width: 0.5,
            ),
            right: BorderSide(
              color: ScrapTheme.dividers.withValues(alpha: 0.85),
              width: 0.5,
            ),
            bottom: isActive
                ? BorderSide.none
                : BorderSide(
                    color: ScrapTheme.dividers.withValues(alpha: 0.85),
                    width: 0.5,
                  ),
          )
        : Border(
            top: BorderSide(
              color: isActive ? tab.accent : ScrapTheme.dividers,
              width: isActive ? 3 : 1,
            ),
            left: const BorderSide(color: ScrapTheme.dividers, width: 0.5),
            right: const BorderSide(color: ScrapTheme.dividers, width: 0.5),
            // Active tab merges into canvas — no bottom border
            bottom: isActive
                ? BorderSide.none
                : const BorderSide(color: ScrapTheme.dividers, width: 0.5),
          );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: EdgeInsets.only(right: 4, top: isActive ? 0 : 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: isActive
              ? (isEphemeral
                  ? ScrapTheme.codeSurface
                  : ScrapTheme.cardSurface)
              : ScrapTheme.codeSurface.withValues(
                  alpha: isEphemeral ? 0.65 : 1,
                ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          border: borderStyle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEphemeral) ...[
              Text(
                '~',
                style: ScrapTextStyles.stamp.copyWith(
                  fontSize: 11,
                  color: ScrapTheme.mutedText,
                ),
              ),
              const SizedBox(width: 4),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                tab.title,
                style: isActive
                    ? ScrapTextStyles.body.copyWith(
                        fontSize: 12,
                        color: isEphemeral
                            ? ScrapTheme.secondaryText
                            : ScrapTheme.primaryText,
                        fontWeight: FontWeight.w600,
                        fontStyle: isEphemeral
                            ? FontStyle.italic
                            : FontStyle.normal,
                      )
                    : ScrapTextStyles.stamp.copyWith(
                        fontSize: 10,
                        color: ScrapTheme.secondaryText,
                        fontStyle: isEphemeral
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (groupName != null) ...[
              const SizedBox(width: 4),
              Text(
                groupName![0],
                style: TextStyle(fontSize: 9, color: tab.accent),
              ),
            ],
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClose,
              child: Icon(
                Icons.close,
                size: 12,
                color: isActive ? ScrapTheme.secondaryText : ScrapTheme.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab context menu sheet ──────────────────────────────────────
class _TabMenuSheet extends ConsumerStatefulWidget {
  final OpenedTab tab;
  final List<OpenedTab> tabs;
  final List<TabGroup> groups;
  const _TabMenuSheet({required this.tab, required this.tabs, required this.groups});

  @override
  ConsumerState<_TabMenuSheet> createState() => _TabMenuSheetState();
}

class _TabMenuSheetState extends ConsumerState<_TabMenuSheet> {
  @override
  Widget build(BuildContext context) {
    final isEphemeral =
        ref.watch(ephemeralNoteIdsProvider).contains(widget.tab.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ScrapTheme.kraft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: widget.tab.accent, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Flexible(child: Text(widget.tab.title,
                style: ScrapTextStyles.heading.copyWith(fontSize: 16))),
          ]),
          const SizedBox(height: 20),

          _MenuItem(icon: Icons.layers_outlined, label: 'Group with another tab', onTap: () {
            Navigator.pop(context);
            _groupDialog(context);
          }),
          if (isEphemeral)
            _MenuItem(
              icon: Icons.delete_outline,
              label: 'Crush loose scrap',
              onTap: () {
                discardEphemeralNote(ref, widget.tab.id);
                Navigator.pop(context);
              },
            )
          else
            _MenuItem(icon: Icons.close, label: 'Close this tab', onTap: () {
              final updated = widget.tabs.where((t) => t.id != widget.tab.id).toList();
              ref.read(openedTabsProvider.notifier).state = updated;
              Navigator.pop(context);
            }),
          _MenuItem(icon: Icons.close_fullscreen_outlined, label: 'Close all other tabs', onTap: () {
            // Crush other loose scraps when keeping this tab alone.
            final ephemeral = ref.read(ephemeralNoteIdsProvider);
            for (final t in widget.tabs) {
              if (t.id != widget.tab.id && ephemeral.contains(t.id)) {
                discardEphemeralNote(ref, t.id);
              }
            }
            ref.read(openedTabsProvider.notifier).state = [widget.tab];
            ref.read(activeTabIdProvider.notifier).state = widget.tab.id;
            Navigator.pop(context);
          }),
        ],
      ),
    );
  }

  void _groupDialog(BuildContext context) {
    final others = widget.tabs.where((t) => t.id != widget.tab.id).toList();
    showScrapDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ScrapTheme.cardSurface,
        title: Text('Group with', style: ScrapTextStyles.heading.copyWith(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: others.map((other) => ListTile(
            leading: Container(width: 8, height: 8,
                decoration: BoxDecoration(color: other.accent, shape: BoxShape.circle)),
            title: Text(other.title, style: ScrapTextStyles.body),
            onTap: () {
              final groupId = 'grp_${DateTime.now().millisecondsSinceEpoch}';
              final newGroup = TabGroup(id: groupId, name: '${widget.tab.title[0]}${other.title[0]}');
              ref.read(tabGroupsProvider.notifier).update((s) => [...s, newGroup]);
              final tabs = ref.read(openedTabsProvider);
              ref.read(openedTabsProvider.notifier).state = tabs.map((t) =>
                  (t.id == widget.tab.id || t.id == other.id)
                      ? t.copyWith(groupId: groupId)
                      : t).toList();
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }
}

class _BackHomeButton extends StatefulWidget {
  final VoidCallback onTap;

  const _BackHomeButton({required this.onTap});

  @override
  State<_BackHomeButton> createState() => _BackHomeButtonState();
}

class _BackHomeButtonState extends State<_BackHomeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back to the pile',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: ScrapMotion.press,
          curve: Curves.easeOut,
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: ScrapTheme.kraft.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ScrapTheme.dividers),
            ),
            child: const Icon(
              Icons.arrow_back,
              size: 16,
              color: ScrapTheme.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 20, color: ScrapTheme.secondaryText),
    title: Text(label, style: ScrapTextStyles.body),
    contentPadding: EdgeInsets.zero,
    dense: true,
    onTap: onTap,
  );
}

// Dart equivalent of firstWhereOrNull
extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}
