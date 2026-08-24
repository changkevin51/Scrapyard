import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/layout/scrap_layout.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../domain/models/home_node.dart';

/// Shared destinations + create-actions for desk, index strip, and drawer.
class HomeNavActions {
  final String currentFolder;
  final bool hasApiKey;
  final VoidCallback onHome;
  final VoidCallback onSaved;
  final VoidCallback onTrash;
  final VoidCallback onSettings;
  final VoidCallback onNewFolder;
  final VoidCallback onNewScrap;
  final VoidCallback onLooseScrap;
  final VoidCallback onImport;
  final VoidCallback onGuide;
  final VoidCallback onFeedback;

  const HomeNavActions({
    required this.currentFolder,
    required this.hasApiKey,
    required this.onHome,
    required this.onSaved,
    required this.onTrash,
    required this.onSettings,
    required this.onNewFolder,
    required this.onNewScrap,
    required this.onLooseScrap,
    required this.onImport,
    required this.onGuide,
    required this.onFeedback,
  });

  bool get inTrash => currentFolder == trashFolderId;
}

/// Vertical filing list used in the landscape sidebar and the phone drawer.
class HomeNavPanel extends StatelessWidget {
  final HomeNavActions actions;
  final bool forDrawer;
  final VoidCallback? onAfterNavigate;

  const HomeNavPanel({
    super.key,
    required this.actions,
    this.forDrawer = false,
    this.onAfterNavigate,
  });

  void _go(VoidCallback dest) {
    // Close the drawer before pushing a route so pop doesn't dismiss Settings.
    onAfterNavigate?.call();
    dest();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final topGap = forDrawer ? 16.0 : math.max(48.0, pad.top);
    final logoWidth = forDrawer
        ? 184.0
        : math.min(184.0, ScrapLayout.sidebarWidth - pad.left - 48);

    Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: forDrawer ? 0 : topGap),
        Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: forDrawer ? 8 : 16,
          ),
          child: Image.asset(
            'assets/images/HomeLogo.png',
            width: logoWidth,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(height: 38),
        HomeNavItem(
          title: 'Home',
          isSelected: actions.currentFolder == 'root',
          onTap: () => _go(actions.onHome),
        ),
        HomeNavItem(
          title: 'Saved',
          isSelected: actions.currentFolder == savedFolderId,
          onTap: () => _go(actions.onSaved),
        ),
        HomeNavItem(
          title: 'Recently Deleted',
          isSelected: actions.inTrash,
          onTap: () => _go(actions.onTrash),
        ),
        HomeNavItem(
          title: 'Settings',
          isSelected: false,
          onTap: () => _go(actions.onSettings),
        ),
        if (actions.hasApiKey)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 8),
            child: Text(
              '⟨ AI key connected ⟩',
              style: ScrapTextStyles.label.copyWith(
                color: ScrapTheme.accent,
                letterSpacing: 0.8,
              ),
            ),
          ),
      ],
    );

    final footer = actions.inTrash
        ? Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
            child: Text(
              'Crushed scraps linger here for ${trashRetention.inDays} days, then vanish for good.',
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.mutedText,
                height: 1.45,
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CreateLink(
                  label: '+  New folder',
                  onTap: actions.onNewFolder,
                ),
                _CreateLink(
                  label: '↑  Import a PDF/doc',
                  onTap: actions.onImport,
                ),
                _CreateLink(
                  label: '?  Guide',
                  onTap: () => _go(actions.onGuide),
                ),
                _CreateLink(
                  label: '*  Feedback',
                  onTap: () => _go(actions.onFeedback),
                ),
              ],
            ),
          );

    final slivers = [
      SliverToBoxAdapter(child: column),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            footer,
            const SizedBox(height: 32),
          ],
        ),
      ),
    ];

    Widget scroller = CustomScrollView(slivers: slivers);

    if (forDrawer) {
      scroller = SafeArea(child: scroller);
    } else {
      scroller = Padding(
        padding: EdgeInsets.only(
          left: pad.left,
          bottom: pad.bottom,
        ),
        child: scroller,
      );
    }

    return scroller;
  }
}

/// Top paper strip for portrait-tablet (index) chrome.
class HomeIndexStrip extends StatelessWidget {
  final HomeNavActions actions;
  final double logoWidth;

  const HomeIndexStrip({
    super.key,
    required this.actions,
    required this.logoWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ScrapTheme.background,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ScrapTheme.dividers, width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Image.asset(
                'assets/images/HomeLogo.png',
                width: logoWidth,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      HomeNavItem(
                        title: 'Home',
                        isSelected: actions.currentFolder == 'root',
                        horizontal: true,
                        onTap: actions.onHome,
                      ),
                      HomeNavItem(
                        title: 'Saved',
                        isSelected: actions.currentFolder == savedFolderId,
                        horizontal: true,
                        onTap: actions.onSaved,
                      ),
                      HomeNavItem(
                        title: 'Deleted',
                        isSelected: actions.inTrash,
                        horizontal: true,
                        onTap: actions.onTrash,
                      ),
                      HomeNavItem(
                        title: 'Settings',
                        isSelected: false,
                        horizontal: true,
                        onTap: actions.onSettings,
                      ),
                      HomeNavItem(
                        title: 'Guide',
                        isSelected: false,
                        horizontal: true,
                        onTap: actions.onGuide,
                      ),
                      HomeNavItem(
                        title: 'Feedback',
                        isSelected: false,
                        horizontal: true,
                        onTap: actions.onFeedback,
                      ),
                    ],
                  ),
                ),
              ),
              if (!actions.inTrash) HomeCreateMenuButton(actions: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim phone bar: menu + logo. Create actions live in the drawer.
class HomeCompactBar extends StatelessWidget {
  final double logoWidth;

  const HomeCompactBar({super.key, required this.logoWidth});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ScrapTheme.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Index',
                icon: const Icon(
                  Icons.menu,
                  color: ScrapTheme.primaryText,
                ),
                onPressed: () {
                  ScrapFeedback.tap();
                  Scaffold.of(context).openDrawer();
                },
              ),
              Image.asset(
                'assets/images/HomeLogo.png',
                width: logoWidth,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeCreateMenuButton extends StatelessWidget {
  final HomeNavActions actions;

  const HomeCreateMenuButton({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'New',
      elevation: 1,
      color: ScrapTheme.cardSurface,
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.add, color: ScrapTheme.accent),
      onSelected: (value) {
        ScrapFeedback.tap();
        switch (value) {
          case 'folder':
            actions.onNewFolder();
          case 'scrap':
            actions.onNewScrap();
          case 'loose':
            actions.onLooseScrap();
          case 'import':
            actions.onImport();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'folder',
          child: Text('+  New folder', style: ScrapTextStyles.body),
        ),
        PopupMenuItem(
          value: 'scrap',
          child: Text('+  New scrap', style: ScrapTextStyles.body),
        ),
        PopupMenuItem(
          value: 'loose',
          child: Text(
            '~  Loose scrap',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.mutedText),
          ),
        ),
        PopupMenuItem(
          value: 'import',
          child: Text('↑  Import a PDF/doc', style: ScrapTextStyles.body),
        ),
      ],
    );
  }
}

class HomeNavItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  final bool horizontal;

  const HomeNavItem({
    super.key,
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    return ScrapPressable(
      scale: 0.98,
      onTap: () {
        ScrapFeedback.tap();
        onTap();
      },
      child: AnimatedContainer(
        duration: ScrapMotion.panel,
        curve: ScrapMotion.panelCurve,
        padding: EdgeInsets.symmetric(
          horizontal: horizontal ? 12 : 24,
          vertical: horizontal ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? ScrapTheme.accent.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: horizontal ? MainAxisSize.min : MainAxisSize.max,
          children: [
            AnimatedContainer(
              duration: ScrapMotion.panel,
              curve: ScrapMotion.panelCurve,
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? ScrapTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AnimatedDefaultTextStyle(
              duration: ScrapMotion.panel,
              curve: ScrapMotion.panelCurve,
              style: ScrapTextStyles.body.copyWith(
                color: isSelected
                    ? ScrapTheme.accent
                    : ScrapTheme.secondaryText,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.3,
                fontSize: horizontal ? 14 : 15,
              ),
              child: Text(title),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CreateLink({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScrapPressable(
      scale: 0.96,
      onTap: () {
        ScrapFeedback.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          label,
          style: ScrapTextStyles.body.copyWith(
            color: ScrapTheme.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
