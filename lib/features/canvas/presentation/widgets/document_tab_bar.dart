import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Document Tab Bar
// Koto-themed open note tabs — NOT browser-style.
//
// Design: Horizontal scrollable strip of bookmark-style pill cards.
// Each tab has a 3px colored left-stripe, note title, and close ×.
// Active tab is elevated with a subtle glow from its accent color.
// Grouped tabs share a tinted background connector.
// ─────────────────────────────────────────────────────────────────
class DocumentTabBar extends ConsumerWidget {
  const DocumentTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs     = ref.watch(openedTabsProvider);
    final activeId = ref.watch(activeTabIdProvider);
    final groups   = ref.watch(tabGroupsProvider);

    if (tabs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: KotoTheme.cardSurface,
        border: Border(bottom: BorderSide(color: KotoTheme.dividers, width: 0.5)),
      ),
      child: Row(
        children: [
          // Back button - navigate to home
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: KotoTheme.dividers),
              ),
              child: const Icon(Icons.arrow_back, size: 16, color: KotoTheme.mutedText),
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: tabs.length,
              itemBuilder: (ctx, i) {
                final tab      = tabs[i];
                final isActive = tab.id == activeId;
                final group    = groups.firstWhereOrNull((g) => g.id == tab.groupId);
                return _TabChip(
                  tab: tab,
                  isActive: isActive,
                  groupName: group?.name,
                  onTap: () {
                    ref.read(activeTabIdProvider.notifier).state = tab.id;
                    ref.read(activeNoteIdProvider.notifier).state = tab.id;
                  },
                  onClose: () {
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
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: KotoTheme.dividers),
              ),
              child: const Icon(Icons.add, size: 16, color: KotoTheme.mutedText),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: KotoTheme.cardSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => _TabMenuSheet(tab: tab, tabs: tabs, groups: groups),
    );
  }
}

// ─── Individual tab chip ─────────────────────────────────────────
class _TabChip extends StatelessWidget {
  final OpenedTab tab;
  final bool isActive;
  final String? groupName;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onLongPress;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.onLongPress,
    this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        decoration: BoxDecoration(
          color: isActive
              ? tab.accent.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(
              color: isActive ? tab.accent : KotoTheme.dividers,
              width: isActive ? 2.5 : 1.5,
            ),
            top: const BorderSide(color: KotoTheme.dividers, width: 0.5),
            right: const BorderSide(color: KotoTheme.dividers, width: 0.5),
            bottom: BorderSide(
              color: isActive ? tab.accent.withValues(alpha: 0.4) : KotoTheme.dividers,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Colored accent dot
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: tab.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            // Title
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                tab.title,
                style: KotoTextStyles.body.copyWith(
                  fontSize: 12,
                  color: isActive ? KotoTheme.primaryText : KotoTheme.secondaryText,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // Group badge
            if (groupName != null) ...[
              const SizedBox(width: 4),
              Text(
                groupName![0],
                style: TextStyle(fontSize: 9, color: tab.accent),
              ),
            ],
            const SizedBox(width: 6),
            // Close
            GestureDetector(
              onTap: onClose,
              child: Icon(
                Icons.close,
                size: 12,
                color: isActive ? KotoTheme.secondaryText : KotoTheme.mutedText,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: widget.tab.accent, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Flexible(child: Text(widget.tab.title,
                style: KotoTextStyles.heading.copyWith(fontSize: 16))),
          ]),
          const SizedBox(height: 20),

          _MenuItem(icon: Icons.layers_outlined, label: 'Group with another tab', onTap: () {
            Navigator.pop(context);
            _groupDialog(context);
          }),
          _MenuItem(icon: Icons.close, label: 'Close this tab', onTap: () {
            final updated = widget.tabs.where((t) => t.id != widget.tab.id).toList();
            ref.read(openedTabsProvider.notifier).state = updated;
            Navigator.pop(context);
          }),
          _MenuItem(icon: Icons.close_fullscreen_outlined, label: 'Close all other tabs', onTap: () {
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KotoTheme.cardSurface,
        title: Text('Group with', style: KotoTextStyles.heading.copyWith(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: others.map((other) => ListTile(
            leading: Container(width: 8, height: 8,
                decoration: BoxDecoration(color: other.accent, shape: BoxShape.circle)),
            title: Text(other.title, style: KotoTextStyles.body),
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

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 20, color: KotoTheme.secondaryText),
    title: Text(label, style: KotoTextStyles.body),
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
