import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../home/domain/models/home_node.dart';
import '../../../home/presentation/providers/home_providers.dart';
import '../providers/canvas_providers.dart';
import 'pending_scrap_flow.dart';

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
    final pendingIds = ref.watch(pendingNewScrapsProvider).keys.toSet();

    if (tabs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: ScrapTheme.background,
        border: Border(bottom: BorderSide(color: ScrapTheme.dividers, width: 0.5)),
      ),
      child: Row(
        children: [
          // Back button - prompt to name/discard pending scraps, then leave.
          _BackHomeButton(
            onTap: () => leaveNoteEditorIfAllowed(context, ref),
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
                final isPending = pendingIds.contains(tab.id);
                final group    = groups.firstWhereOrNull((g) => g.id == tab.groupId);
                return _TabChip(
                  tab: tab,
                  isActive: isActive,
                  isEphemeral: isEphemeral,
                  isPending: isPending,
                  groupName: group?.name,
                  onTap: () => switchActiveNote(ref, tab.id),
                  onClose: () async {
                    if (isPending) {
                      if (activeId != tab.id) {
                        switchActiveNote(ref, tab.id);
                      }
                      final resolved =
                          await resolvePendingScrapForTab(ctx, ref, tab.id);
                      if (!resolved) return;
                      return;
                    }
                    if (isEphemeral) {
                      if (scrapIdHasInk(ref, tab.id)) {
                        if (activeId != tab.id) switchActiveNote(ref, tab.id);
                        final drift = await showLetSheetDriftDialog(ctx);
                        if (drift != true) return;
                      }
                      discardEphemeralNote(ref, tab.id);
                      return;
                    }
                    stashActiveEphemeralCanvas(ref);
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
          const _NewTabButton(),
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
  final bool isPending;
  final String? groupName;
  final VoidCallback onTap;
  final Future<void> Function() onClose;
  final VoidCallback onLongPress;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.isEphemeral,
    required this.isPending,
    required this.onTap,
    required this.onClose,
    required this.onLongPress,
    this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    final isLooseScrap = isEphemeral && !isPending;
    final displayTitle =
        isLooseScrap ? 'Loose scrap' : tab.title;
    final bgColor = isActive
        ? ScrapTheme.cardSurface
        : ScrapTheme.codeSurface.withValues(alpha: isLooseScrap ? 0.65 : 1);
    // Uniform border color is required when using borderRadius — mixed per-side
    // colors throw and can prevent the tab contents from painting.
    final borderColor = isActive ? bgColor : ScrapTheme.dividers;
    final labelStyle = ScrapTextStyles.body.copyWith(
      fontSize: 12,
      color: isLooseScrap ? ScrapTheme.secondaryText : ScrapTheme.primaryText,
      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
      fontStyle: isLooseScrap ? FontStyle.italic : FontStyle.normal,
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: EdgeInsets.only(right: 4, top: isActive ? 0 : 3),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        constraints: const BoxConstraints(minHeight: 28),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLooseScrap) ...[
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
                displayTitle,
                style: labelStyle,
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
              onTap: () => onClose(),
              child: const Icon(
                Icons.close,
                size: 12,
                color: ScrapTheme.secondaryText,
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
    final isPending = isPendingNewScrap(ref, widget.tab.id);
    final isLooseScrap = isEphemeral && !isPending;
    final displayTitle =
        isLooseScrap ? 'Loose scrap' : widget.tab.title;

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
            Flexible(child: Text(displayTitle,
                style: ScrapTextStyles.heading.copyWith(fontSize: 16))),
          ]),
          const SizedBox(height: 20),

          _MenuItem(icon: Icons.layers_outlined, label: 'Group with another tab', onTap: () {
            Navigator.pop(context);
            _groupDialog(context);
          }),
          if (isPending)
            _MenuItem(
              icon: Icons.drive_file_rename_outline,
              label: 'Name & file scrap',
              onTap: () async {
                Navigator.pop(context);
                await resolvePendingScrapForTab(context, ref, widget.tab.id);
              },
            )
          else if (isLooseScrap)
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

class _NewTabButton extends ConsumerWidget {
  const _NewTabButton();

  void _showMenu(BuildContext context, WidgetRef ref, RenderBox button) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: ScrapTheme.cardSurface,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        side: const BorderSide(color: ScrapTheme.dividers),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'new',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New scrap', style: ScrapTextStyles.body),
              Text(
                'Name & file when you leave',
                style: ScrapTextStyles.caption.copyWith(
                  color: ScrapTheme.mutedText,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'loose',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '~  Loose scrap',
                style: ScrapTextStyles.body.copyWith(
                  color: ScrapTheme.secondaryText,
                  fontStyle: FontStyle.italic,
                ),
              ),
              Text(
                'Unsaved — drifts off when you leave',
                style: ScrapTextStyles.caption.copyWith(
                  color: ScrapTheme.mutedText,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'new') {
        ScrapFeedback.tap();
        final folderId = ref.read(currentFolderIdProvider);
        final parentId = folderId == trashFolderId ? 'root' : folderId;
        openNewScrapInTab(ref, parentId: parentId);
      } else if (value == 'loose') {
        openLooseScrapInTab(ref);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: 'New scrap',
      child: Builder(
        builder: (ctx) => GestureDetector(
          onTap: () {
            final box = ctx.findRenderObject() as RenderBox?;
            if (box == null) return;
            _showMenu(context, ref, box);
          },
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: ScrapTheme.kraft.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ScrapTheme.dividers),
            ),
            child: const Icon(Icons.add, size: 16, color: ScrapTheme.mutedText),
          ),
        ),
      ),
    );
  }
}

class _BackHomeButton extends StatefulWidget {
  final Future<void> Function() onTap;

  const _BackHomeButton({required this.onTap});

  @override
  State<_BackHomeButton> createState() => _BackHomeButtonState();
}

class _BackHomeButtonState extends State<_BackHomeButton> {
  bool _pressed = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back to the pile',
      child: GestureDetector(
        onTapDown: _busy ? null : (_) => setState(() => _pressed = true),
        onTapUp: _busy ? null : (_) => setState(() => _pressed = false),
        onTapCancel: _busy ? null : () => setState(() => _pressed = false),
        onTap: _busy
            ? null
            : () async {
                setState(() {
                  _busy = true;
                  _pressed = false;
                });
                try {
                  await widget.onTap();
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
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
