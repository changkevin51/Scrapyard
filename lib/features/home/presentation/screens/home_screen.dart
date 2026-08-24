import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../core/layout/scrap_layout.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_tilt.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_crush.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
import '../../domain/models/home_node.dart';
import '../../data/scrap_share.dart';
import '../providers/home_providers.dart' show
    currentFolderIdProvider,
    currentHomeNodesProvider,
    folderPathProvider,
    homeRepositoryProvider,
    invalidateNoteThumbnail,
    scrapThumbnailPreloaderProvider;
import '../widgets/home_nav_panel.dart';
import '../widgets/pdf_thumbnail.dart';
import '../widgets/scrap_thumbnail.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../../canvas/presentation/widgets/pending_scrap_flow.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/api_key_dialog.dart';
import '../../../feedback/presentation/widgets/feedback_dialog.dart';
import '../../../onboarding/presentation/screens/onboarding_screen.dart';
import '../../../onboarding/presentation/providers/smelt_guide_provider.dart';
import '../../../onboarding/presentation/smelt_guide_keys.dart';
import '../../../splash/presentation/providers/splash_providers.dart';
import '../../../pdf_viewer/presentation/providers/pdf_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _bannerDismissed = false;
  String? _lastWarmedFolderKey;
  final Map<String, GlobalKey> _crushKeys = {};
  String? _draggingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptForApiKey();
      _warmThumbnailsIfReady();
    });
  }

  void _warmThumbnailsIfReady() {
    final nodes = ref.read(currentHomeNodesProvider).valueOrNull;
    if (nodes == null) return;
    final folderId = ref.read(currentFolderIdProvider);
    final key = '$folderId:${nodes.length}:${nodes.map((n) => n.id).join(',')}';
    if (key == _lastWarmedFolderKey) return;
    _lastWarmedFolderKey = key;
    ref.read(scrapThumbnailPreloaderProvider).warmFolder(nodes);
  }

  Future<void> _maybePromptForApiKey() async {
    if (!mounted) return;
    if (ref.read(apiKeySetupPromptedProvider)) return;

    // Wait until the splash overlay has fully exited so the dialog is visible.
    if (!ref.read(appReadyProvider)) {
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        if (ref.read(appReadyProvider)) break;
      }
      if (!mounted || !ref.read(appReadyProvider)) return;
    }

    // Wait briefly for the key to finish loading from secure storage.
    var keyState = ref.read(apiKeyProvider);
    if (keyState.isLoading) {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        keyState = ref.read(apiKeyProvider);
        if (!keyState.isLoading) break;
      }
    }

    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(onboardingCompletedPrefsKey) != true) {
      if (!mounted) return;
      context.go('/onboarding');
      return;
    }

    ref.read(apiKeySetupPromptedProvider.notifier).state = true;

    final key = keyState.valueOrNull;
    if (key == null || key.isEmpty) {
      final saved = await showApiKeyDialog(context, allowSkip: true);
      if (saved == true && mounted) {
        final nowHasKey =
            (ref.read(apiKeyProvider).valueOrNull ?? '').isNotEmpty;
        showPaperToast(
          context,
          nowHasKey ? 'API key saved' : 'API key removed',
        );
        if (nowHasKey) {
          await ref.read(smeltGuideProvider.notifier).startFromHome();
        }
      }
    }
  }

  Future<void> _openApiKeyDialog() async {
    final saved = await showApiKeyDialog(context, allowSkip: true);
    if (saved == true && mounted) {
      final nowHasKey =
          (ref.read(apiKeyProvider).valueOrNull ?? '').isNotEmpty;
      showPaperToast(
        context,
        nowHasKey ? 'API key saved' : 'API key removed',
      );
      if (nowHasKey) {
        await ref.read(smeltGuideProvider.notifier).startFromHome();
      }
    }
  }

  void _notifyGuideOpenedScrap() {
    ref.read(smeltGuideProvider.notifier).notifyOpenedScrap();
  }

  Future<void> _createAndOpenScrap() async {
    final folderId = ref.read(currentFolderIdProvider);
    final parentId =
        (folderId == trashFolderId || folderId == savedFolderId) ? 'root' : folderId;
    final node = HomeNode.create(
      title: 'New scrap',
      type: NodeType.note,
      parentId: parentId,
    );
    if (!mounted) return;
    ref.read(pendingNewScrapsProvider.notifier).update((m) => {...m, node.id: node});
    openNoteTab(ref, node.id, node.title, ephemeral: true);
    _notifyGuideOpenedScrap();
    context.push('/note_editor').then((_) => _onNoteEditorClosed(node.id));
  }

  Future<void> _onNewFolder() async {
    ScrapFeedback.tap();
    final title = await showScrapDialog<String>(
      context: context,
      builder: (ctx) => const _RenameNodeDialog(
        initialTitle: 'New Folder',
        dialogTitle: 'New pile',
      ),
    );
    if (title == null || !mounted) return;
    await ref.read(currentHomeNodesProvider.notifier).createFolder(title);
  }

  void _openLooseScrap() {
    ScrapFeedback.action();
    final id = 'loose-${DateTime.now().microsecondsSinceEpoch}';
    openNoteTab(ref, id, 'Loose scrap', ephemeral: true);
    _notifyGuideOpenedScrap();
    context.push('/note_editor').then((_) {
      if (ref.read(ephemeralNoteIdsProvider).isNotEmpty) {
        discardAllEphemeralNotes(ref);
      }
      ref.read(dirtyNoteIdsProvider.notifier).state = {};
    });
  }

  void _openPdf(WidgetRef ref, HomeNode node) {
    final path = node.externalPath;
    if (path == null || path.isEmpty) return;
    ScrapFeedback.tap();
    ref.read(activePdfPathProvider.notifier).state = path;
    ref.read(activePdfTitleProvider.notifier).state = node.title;
    ref.read(pdfDocumentIdProvider.notifier).state = node.id;
    context.push('/pdf_viewer');
  }

  /// Refresh home timestamps/thumbnails after canvas edits.
  Future<void> _onNoteEditorClosed(String noteId) async {
    // If the editor was dismissed without resolving (e.g. system back race),
    // still offer to name/file pending scraps from home.
    final pending = ref.read(pendingNewScrapsProvider);
    if (pending.isNotEmpty && mounted) {
      final canLeave = await resolvePendingScrapsBeforeLeaving(context, ref);
      if (!canLeave) {
        // User cancelled — reopen the desk so the scrap isn't lost.
        if (!mounted) return;
        final pendingId = ref.read(activeNoteIdProvider);
        final id = pending.containsKey(pendingId)
            ? pendingId
            : pending.keys.first;
        final title = pending[id]?.title ?? 'New scrap';
        openNoteTab(ref, id, title, ephemeral: true);
        _notifyGuideOpenedScrap();
        context.push('/note_editor').then((_) => _onNoteEditorClosed(id));
        return;
      }
    }

    final dirty = ref.read(dirtyNoteIdsProvider);
    final ephemeral = ref.read(ephemeralNoteIdsProvider);
    final toTouch = dirty.where((id) => !ephemeral.contains(id)).toSet();

    if (toTouch.isNotEmpty) {
      await ref.read(currentHomeNodesProvider.notifier).touchNotes(toTouch);
      for (final id in toTouch) {
        invalidateNoteThumbnail(ref, id);
      }
    } else {
      invalidateNoteThumbnail(ref, noteId);
    }

    ref.read(dirtyNoteIdsProvider.notifier).state = {};
    // Pending should already be empty after resolve; never silently wipe.
    discardAllEphemeralNotes(ref);
  }

  @override
  Widget build(BuildContext context) {
    final nodesAsync = ref.watch(currentHomeNodesProvider);
    final currentFolder = ref.watch(currentFolderIdProvider);
    final folderPath = ref.watch(folderPathProvider);
    final apiKeyAsync = ref.watch(apiKeyProvider);
    final hasApiKey = (apiKeyAsync.valueOrNull ?? '').isNotEmpty;
    final showBanner =
        !hasApiKey && !_bannerDismissed && !apiKeyAsync.isLoading;

    // Warm first rows ASAP, then trickle the rest — do not wait for scroll.
    ref.listen<AsyncValue<List<HomeNode>>>(currentHomeNodesProvider, (prev, next) {
      next.whenData((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _warmThumbnailsIfReady();
        });
      });
    });

    final layout = ScrapLayout.of(context);
    final nav = _homeNavActions(currentFolder, hasApiKey);

    Widget desk = ColoredBox(
      color: ScrapTheme.background,
      child: Padding(
        padding: EdgeInsets.all(layout.deskPadding),
        child: CustomScrollView(
                  slivers: [
                    if (showBanner) ...[
                      SliverToBoxAdapter(
                        child: _ApiKeyBanner(
                          onSetup: _openApiKeyDialog,
                          onDismiss: () =>
                              setState(() => _bannerDismissed = true),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                    if (currentFolder != trashFolderId &&
                        currentFolder != savedFolderId) ...[
                      SliverToBoxAdapter(
                        child: _NewScrapButton(
                          compact: layout.compactCta,
                          onTap: _createAndOpenScrap,
                          onLooseTap: _openLooseScrap,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: layout.compactCta ? 24 : 40),
                      ),
                    ],

                    // Breadcrumb Navigation
                    SliverToBoxAdapter(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: AnimatedSlide(
                              duration: ScrapMotion.panel,
                              curve: ScrapMotion.panelCurve,
                              offset: currentFolder == 'root' ||
                                      currentFolder == trashFolderId ||
                                      currentFolder == savedFolderId
                                  ? const Offset(-0.35, 0)
                                  : Offset.zero,
                              child: AnimatedOpacity(
                                duration: ScrapMotion.panel,
                                curve: ScrapMotion.panelCurve,
                                opacity: currentFolder == 'root' ||
                                        currentFolder == trashFolderId ||
                                        currentFolder == savedFolderId
                                    ? 0.0
                                    : 1.0,
                                child: IgnorePointer(
                                  ignoring: currentFolder == 'root' ||
                                      currentFolder == trashFolderId ||
                                      currentFolder == savedFolderId,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: ScrapTheme.primaryText,
                                    ),
                                    onPressed: _popHomeFolder,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: ScrapMotion.panel,
                              switchInCurve: ScrapMotion.panelCurve,
                              switchOutCurve: ScrapMotion.panelCurve,
                              layoutBuilder:
                                  (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              transitionBuilder: (child, animation) {
                                final fade = CurvedAnimation(
                                  parent: animation,
                                  curve: const Interval(0.45, 1.0),
                                );
                                return FadeTransition(
                                  opacity: fade,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.12),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: Text(
                                currentFolder == trashFolderId
                                    ? 'Recently Deleted'
                                    : currentFolder == savedFolderId
                                        ? 'Saved'
                                        : currentFolder == 'root'
                                            ? 'All Files'
                                            : folderPath.isNotEmpty
                                                ? folderPath.last.title
                                                : 'All Files',
                                key: ValueKey(currentFolder),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ScrapTextStyles.heading
                                    .copyWith(fontSize: layout.headerTitleSize),
                              ),
                            ),
                          ),
                          if (currentFolder == trashFolderId)
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: PaperButton(
                              label: 'Empty trash',
                              variant: PaperButtonVariant.danger,
                              compact: true,
                              icon: Icons.delete_forever_outlined,
                              onPressed:
                                  (nodesAsync.valueOrNull?.isNotEmpty ?? false)
                                      ? () =>
                                          _confirmEmptyTrash(context, ref)
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (currentFolder == trashFolderId)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(left: layout.subtitleInset, top: 8),
                          child: Text(
                            'Items stay here for ${trashRetention.inDays} days, then they\'re permanently crushed.',
                            style: ScrapTextStyles.caption.copyWith(
                              color: ScrapTheme.mutedText,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    if (currentFolder == savedFolderId)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(left: layout.subtitleInset, top: 8),
                          child: Text(
                            'Starred scraps and PDFs live here. They can still be accessed from their original location.',
                            style: ScrapTextStyles.caption.copyWith(
                              color: ScrapTheme.mutedText,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),

                    // Grid View of Nodes — remount on folder change so
                    // cards get a brief staggered scrap entrance.
                    ...nodesAsync.when(
                      loading: () => [
                        const SliverToBoxAdapter(
                          child: SizedBox(
                            height: 240,
                            child: Center(child: PaperDots()),
                          ),
                        ),
                      ],
                      error: (err, stack) => [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: Column(
                                children: [
                                  Text(
                                    "Couldn't load this pile.",
                                    style: ScrapTextStyles.caption.copyWith(
                                      color: ScrapTheme.mutedText,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  PaperButton(
                                    label: 'Retry',
                                    variant: PaperButtonVariant.secondary,
                                    compact: true,
                                    onPressed: () => ref
                                        .read(currentHomeNodesProvider.notifier)
                                        .refresh(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      data: (nodes) {
                        if (nodes.isEmpty) {
                          return [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: Text(
                                    currentFolder == trashFolderId
                                        ? 'Nothing crushed yet. Soft landings only.'
                                        : currentFolder == savedFolderId
                                            ? 'Nothing pinned yet. Star a scrap or PDF to keep it here.'
                                            : 'Empty folder. Grab a scrap above, or import a doc.',
                                    style: ScrapTextStyles.caption.copyWith(
                                      color: ScrapTheme.mutedText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ];
                        }

                        final files = homeFileNodes(nodes);
                        final folders = homeFolderNodes(nodes);
                        return [
                          if (folders.isNotEmpty)
                            _buildNodeGrid(
                              context,
                              ref,
                              folders,
                              gridKey: '$currentFolder-piles',
                              pileLayout: true,
                            ),
                          if (files.isNotEmpty && folders.isNotEmpty)
                            const SliverToBoxAdapter(
                              child: _PilesSectionDivider(),
                            ),
                          if (files.isNotEmpty)
                            _buildNodeGrid(
                              context,
                              ref,
                              files,
                              gridKey: '$currentFolder-files',
                            ),
                        ];
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
      ),
    );

    if (!layout.showSidebar) {
      desk = SafeArea(top: false, child: desk);
    }

    return PopScope(
      canPop: currentFolder == 'root',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popHomeFolder();
      },
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      drawer: layout.isCompact
          ? Drawer(
              width: layout.drawerWidth,
              backgroundColor: ScrapTheme.background,
              shape: const RoundedRectangleBorder(),
              child: Builder(
                builder: (drawerContext) {
                  return HomeNavPanel(
                    actions: nav,
                    forDrawer: true,
                    onAfterNavigate: () {
                      Navigator.of(drawerContext).pop();
                    },
                  );
                },
              ),
            )
          : null,
      body: layout.showSidebar
          ? Row(
              children: [
                Container(
                  width: ScrapLayout.sidebarWidth,
                  decoration: const BoxDecoration(
                    color: ScrapTheme.background,
                    border: Border(
                      right: BorderSide(
                        color: ScrapTheme.dividers,
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: HomeNavPanel(actions: nav),
                ),
                Expanded(child: desk),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (layout.isIndex)
                  HomeIndexStrip(
                    actions: nav,
                    logoWidth: layout.logoWidth,
                  ),
                if (layout.isCompact)
                  HomeCompactBar(logoWidth: layout.logoWidth),
                Expanded(child: desk),
              ],
            ),
      ),
    );
  }

  void _popHomeFolder() {
    final currentFolder = ref.read(currentFolderIdProvider);
    if (currentFolder == 'root') return;
    final path = ref.read(folderPathProvider);
    if (currentFolder == trashFolderId ||
        currentFolder == savedFolderId ||
        path.length <= 1) {
      ref.read(currentFolderIdProvider.notifier).state = 'root';
      ref.read(folderPathProvider.notifier).state = [];
      return;
    }
    ref.read(currentFolderIdProvider.notifier).state = path[path.length - 2].id;
    ref.read(folderPathProvider.notifier).state =
        path.sublist(0, path.length - 1);
  }

  HomeNavActions _homeNavActions(String currentFolder, bool hasApiKey) {
    return HomeNavActions(
      currentFolder: currentFolder,
      hasApiKey: hasApiKey,
      onHome: () {
        ref.read(currentFolderIdProvider.notifier).state = 'root';
        ref.read(folderPathProvider.notifier).state = [];
      },
      onSaved: () {
        ref.read(currentFolderIdProvider.notifier).state = savedFolderId;
        ref.read(folderPathProvider.notifier).state = [];
      },
      onTrash: () {
        ref.read(currentFolderIdProvider.notifier).state = trashFolderId;
        ref.read(folderPathProvider.notifier).state = [];
      },
      onSettings: () => context.push('/settings'),
      onNewFolder: _onNewFolder,
      onNewScrap: _createAndOpenScrap,
      onLooseScrap: _openLooseScrap,
      onImport: () async {
        final message =
            await ref.read(currentHomeNodesProvider.notifier).importDocument();
        if (!mounted || message == null) return;
        showPaperToast(context, message);
      },
      onGuide: () => context.push('/guide'),
      onFeedback: () => showFeedbackDialog(context),
    );
  }

  Widget _buildNodeGrid(
    BuildContext context,
    WidgetRef ref,
    List<HomeNode> nodes, {
    required String gridKey,
    bool pileLayout = false,
  }) {
    final layout = ScrapLayout.of(context);
    return SliverGrid(
      key: ValueKey(gridKey),
      gridDelegate: pileLayout
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.pileColumns,
              crossAxisSpacing: layout.gridGap,
              mainAxisSpacing: layout.pileMainAxisSpacing,
              mainAxisExtent: layout.pileExtent,
            )
          : SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.fileColumns,
              crossAxisSpacing: layout.gridGap,
              mainAxisSpacing: layout.gridGap,
              childAspectRatio: layout.fileAspectRatio,
            ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final node = nodes[index];
          return ScrapCardEntrance(
            index: index,
            stagger: const Duration(milliseconds: 28),
            child: RepaintBoundary(
              key: _crushKeys.putIfAbsent(node.id, GlobalKey.new),
              child: ScrapTilt(
                key: ValueKey(node.id),
                seed: node.id.hashCode,
                maxDegrees: pileLayout ? 0.6 : 1.2,
                child: _buildNodeCard(context, ref, node),
              ),
            ),
          );
        },
        childCount: nodes.length,
      ),
    );
  }

  Future<void> _onDropOntoFolder(
    BuildContext context,
    WidgetRef ref,
    HomeNode incoming,
    HomeNode folder,
  ) async {
    ScrapFeedback.action();
    final ok = await ref
        .read(currentHomeNodesProvider.notifier)
        .moveNode(incoming.id, folder.id);
    if (!context.mounted) return;
    if (ok) {
      showPaperToast(context, 'Tucked into "${folder.title}"');
    } else {
      showPaperToast(context, 'Couldn\'t move into that pile');
    }
  }

  Widget _wrapDeskDrag({
    required HomeNode node,
    required bool enabled,
    required Widget child,
  }) {
    if (!enabled) return child;
    return LongPressDraggable<HomeNode>(
      data: node,
      delay: ScrapMotion.dragHold,
      hapticFeedbackOnStart: false,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: (draggable, context, position) =>
          node.type == NodeType.folder
              ? const Offset(100, 32)
              : const Offset(84, 76),
      onDragStarted: () {
        ScrapFeedback.action();
        setState(() => _draggingId = node.id);
      },
      onDragEnd: (_) {
        if (mounted) setState(() => _draggingId = null);
      },
      onDraggableCanceled: (_, __) {
        if (mounted) setState(() => _draggingId = null);
      },
      feedback: _MinimizedDragFeedback(node: node),
      childWhenDragging: const _DeskSlotGhost(),
      child: child,
    );
  }

  Widget _buildNodeCard(BuildContext context, WidgetRef ref, HomeNode node) {
    final folderId = ref.read(currentFolderIdProvider);
    final inTrash = folderId == trashFolderId;
    final enableDrag = !inTrash && folderId != savedFolderId;

    Widget card = ScrapPressable(
      onTap: () {
        if (inTrash) {
          if (node.type == NodeType.folder) {
            ScrapFeedback.tap();
            showPaperToast(context, 'Restore this pile to open it');
            return;
          }
          if (node.type == NodeType.document) {
            if (node.externalPath != null &&
                node.externalPath!.toLowerCase().endsWith('.pdf')) {
              _openPdf(ref, node);
            } else if (node.externalPath != null) {
              OpenFilex.open(node.externalPath!);
            }
            return;
          }
          if (node.type == NodeType.note) {
            ref.read(activeNoteIdProvider.notifier).state = node.id;
            openNoteTab(ref, node.id, node.title);
            _notifyGuideOpenedScrap();
            context
                .push('/note_editor')
                .then((_) => _onNoteEditorClosed(node.id));
          }
          return;
        }

        if (node.type == NodeType.folder) {
          ScrapFeedback.action();
          ref.read(currentFolderIdProvider.notifier).state = node.id;
          ref.read(folderPathProvider.notifier).state = [
            ...ref.read(folderPathProvider),
            node,
          ];
        } else if (node.type == NodeType.document) {
          if (node.externalPath != null &&
              node.externalPath!.toLowerCase().endsWith('.pdf')) {
            _openPdf(ref, node);
          } else if (node.externalPath != null) {
            OpenFilex.open(node.externalPath!);
          }
        } else if (node.type == NodeType.note) {
          // Set the active note ID BEFORE navigating so the editor
          // loads this specific note's strokes.
          ref.read(activeNoteIdProvider.notifier).state = node.id;
          openNoteTab(ref, node.id, node.title);
          _notifyGuideOpenedScrap();
          context.push('/note_editor').then((_) => _onNoteEditorClosed(node.id));
        }
      },
      child: node.type == NodeType.folder
          ? DragTarget<HomeNode>(
              onWillAcceptWithDetails: (details) =>
                  canDropOntoFolder(details.data, node),
              onAcceptWithDetails: (details) => _onDropOntoFolder(
                context,
                ref,
                details.data,
                node,
              ),
              builder: (context, candidate, rejected) {
                final awaiting = _draggingId != null &&
                    _draggingId != node.id &&
                    candidate.isEmpty;
                return _buildPileCard(
                  context,
                  ref,
                  node,
                  receiving: candidate.isNotEmpty,
                  awaiting: awaiting,
                );
              },
            )
          : _buildFlatCard(context, ref, node),
    );

    return _wrapDeskDrag(
      node: node,
      enabled: enableDrag,
      child: card,
    );
  }

  /// Scrap / document card — single flat sheet.
  Widget _buildFlatCard(BuildContext context, WidgetRef ref, HomeNode node) {
    final isScrap = node.type == NodeType.note;
    final hasPreview = isScrap || node.isPdf;
    final typeLabel = isScrap ? '⟨ Scrap ⟩' : '⟨ Document ⟩';
    final compact = ScrapLayout.of(context).compactCards;
    final previewPad = compact
        ? const EdgeInsets.fromLTRB(8, 8, 8, 0)
        : const EdgeInsets.fromLTRB(16, 16, 16, 0);
    final metaPad = compact
        ? const EdgeInsets.fromLTRB(16, 10, 16, 12)
        : EdgeInsets.fromLTRB(28, hasPreview ? 16 : 0, 28, 28);
    final headerPad = compact
        ? const EdgeInsets.fromLTRB(12, 12, 8, 0)
        : const EdgeInsets.fromLTRB(28, 28, 16, 0);

    final card = Container(
      decoration: BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      clipBehavior: isScrap ? Clip.none : Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPreview)
            Expanded(
              child: Padding(
                padding: previewPad,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ScrapTheme.background,
                    borderRadius:
                        BorderRadius.circular(ScrapTheme.borderRadiusSmall),
                    boxShadow: ScrapTheme.subtleShadow,
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(ScrapTheme.borderRadiusSmall),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: isScrap
                              ? ScrapThumbnail(noteId: node.id)
                              : PdfThumbnail(nodeId: node.id),
                        ),
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xE6F5F4F0),
                                  Color(0x00F5F4F0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 16,
                          right: 4,
                          child: _cardHeader(context, ref, node, typeLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: headerPad,
              child: _cardHeader(context, ref, node, typeLabel),
            ),
            const Spacer(),
          ],
          Padding(
            padding: metaPad,
            child: _cardMeta(node, compact: compact),
          ),
        ],
      ),
    );

    // Scraps get a torn bottom edge painted in page colour (no ClipPath layer).
    if (!isScrap) return card;
    return CustomPaint(
      foregroundPainter: TornEdgePainter(
        seed: node.id.hashCode,
        amplitude: 4.0,
      ),
      child: card,
    );
  }

  /// Pile card — stacked sheets with a warm folder tab, sized as a short
  /// strip so piles sit above the file grid without competing for height.
  Widget _buildPileCard(
    BuildContext context,
    WidgetRef ref,
    HomeNode node, {
    bool receiving = false,
    bool awaiting = false,
  }) {
    final seed = node.id.hashCode;
    final spread = receiving ? 8.0 : (awaiting ? 5.5 : 4.0);
    final accentAlpha = receiving ? 0.42 : (awaiting ? 0.28 : 0.18);

    return AnimatedPadding(
      duration: ScrapMotion.press,
      curve: ScrapMotion.panelCurve,
      padding: EdgeInsets.only(top: receiving ? 2 : 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: spread + 2,
            left: spread + 2,
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: ((seed % 7) - 3) * 0.012,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ScrapTheme.kraft,
                  borderRadius:
                      BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                ),
              ),
            ),
          ),
          Positioned(
            top: spread / 2,
            left: spread / 2,
            right: 2,
            bottom: 2,
            child: Transform.rotate(
              angle: (((seed ~/ 11) % 7) - 3) * 0.01,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ScrapTheme.tape,
                  borderRadius:
                      BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: ScrapMotion.press,
              curve: ScrapMotion.panelCurve,
              decoration: BoxDecoration(
                color: ScrapTheme.accentSurface,
                borderRadius:
                    BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                border: Border.all(
                  color: ScrapTheme.accent.withValues(alpha: accentAlpha),
                  width: receiving ? 1.5 : 1,
                ),
                // Keep blur identical across states — easeOutBack-style
                // overshoot on a 12→0 lerp made Shadow.blurRadius negative.
                boxShadow: [
                  BoxShadow(
                    color: Color(receiving ? 0x14000000 : 0x08000000),
                    offset: Offset(0, receiving ? 2 : 4),
                    blurRadius: 12,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: ScrapTheme.accent.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(2),
                              bottomRight: Radius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const _PileStackGraphic(compact: true),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ScrapStampLabel(
                              text: receiving ? '⟨ tuck in ⟩' : '⟨ Pile ⟩',
                              color: ScrapTheme.accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            node.title,
                            style: ScrapTextStyles.heading.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _cardHeaderActions(context, ref, node),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNodeUpdatedAt(DateTime updatedAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final updatedDay =
        DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final date = '${updatedAt.month}/${updatedAt.day}';

    String? dayLabel;
    if (updatedDay == today) {
      dayLabel = 'today';
    } else if (updatedDay == today.subtract(const Duration(days: 1))) {
      dayLabel = 'yesterday';
    }

    if (dayLabel != null) {
      final hour = updatedAt.hour;
      final minute = updatedAt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour % 12 == 0 ? 12 : hour % 12;
      return 'Updated $dayLabel at $hour12:$minute $period';
    }

    return 'Updated $date';
  }

  Widget _cardMeta(HomeNode node, {bool compact = false}) {
    final inTrash = node.isDeleted;
    final daysLeft = node.trashDaysRemaining;
    final subtitle = inTrash && daysLeft != null
        ? (daysLeft == 0
            ? 'Crushed · vanishes today'
            : daysLeft == 1
                ? 'Crushed · 1 day left'
                : 'Crushed · $daysLeft days left')
        : _formatNodeUpdatedAt(node.updatedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          node.title,
          style: ScrapTextStyles.heading.copyWith(
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ScrapTextStyles.caption.copyWith(
            fontSize: compact ? 12 : 14,
            color: inTrash ? ScrapTheme.inkRed.withValues(alpha: 0.75) : ScrapTheme.mutedText,
          ),
        ),
      ],
    );
  }

  /// Snapshot the card and play the crush overlay; the node is soft-deleted
  /// as soon as the snapshot is captured so the grid reflows under the animation.
  void _crushNode(BuildContext context, WidgetRef ref, HomeNode node) {
    ScrapFeedback.warn();
    final key = _crushKeys.remove(node.id);
    ScrapCrush.crush(
      context,
      key,
      onCrushed: () async {
        await ref
            .read(currentHomeNodesProvider.notifier)
            .moveToTrash(node.id);
        if (context.mounted) {
          showPaperToast(context, 'Moved to Recently Deleted');
        }
      },
    );
  }

  Future<void> _restoreNode(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
  ) async {
    ScrapFeedback.action();
    await ref.read(currentHomeNodesProvider.notifier).restoreFromTrash(node.id);
    if (context.mounted) {
      showPaperToast(context, 'Restored "${node.title}"');
    }
  }

  Future<void> _permanentlyCrushNode(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
  ) async {
    ScrapFeedback.warn();
    final confirmed = await showScrapDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ScrapTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        ),
        title: Text('Crush forever?', style: ScrapTextStyles.heading),
        content: Text(
          '"${node.title}" will be permanently deleted. This cannot be undone.',
          style: ScrapTextStyles.body,
        ),
        actions: [
          PaperButton(
            label: 'Cancel',
            variant: PaperButtonVariant.ghost,
            compact: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          PaperButton(
            label: 'Crush forever',
            variant: PaperButtonVariant.danger,
            compact: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !context.mounted) return;

    final key = _crushKeys.remove(node.id);
    ScrapCrush.crush(
      context,
      key,
      onCrushed: () async {
        await ref
            .read(currentHomeNodesProvider.notifier)
            .permanentlyDelete(node.id);
        final tabs = ref
            .read(openedTabsProvider)
            .where((t) => t.id != node.id)
            .toList();
        ref.read(openedTabsProvider.notifier).state = tabs;
      },
    );
  }

  Future<void> _confirmEmptyTrash(BuildContext context, WidgetRef ref) async {
    final nodes = ref.read(currentHomeNodesProvider).valueOrNull ?? [];
    if (nodes.isEmpty) {
      showPaperToast(context, 'Trash is already empty');
      return;
    }

    ScrapFeedback.warn();
    final confirmed = await showScrapDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ScrapTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        ),
        title: Text('Empty trash?', style: ScrapTextStyles.heading),
        content: Text(
          'Permanently crush everything in Recently Deleted. This cannot be undone.',
          style: ScrapTextStyles.body,
        ),
        actions: [
          PaperButton(
            label: 'Cancel',
            variant: PaperButtonVariant.ghost,
            compact: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          PaperButton(
            label: 'Crush everything',
            variant: PaperButtonVariant.danger,
            compact: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(currentHomeNodesProvider.notifier).emptyTrash();
    if (context.mounted) {
      showPaperToast(context, 'Trash emptied');
    }
  }

  Future<void> _renameNode(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
  ) async {
    final newTitle = await showScrapDialog<String>(
      context: context,
      builder: (ctx) => _RenameNodeDialog(initialTitle: node.title),
    );

    if (newTitle == null || !mounted) return;

    await ref
        .read(currentHomeNodesProvider.notifier)
        .renameNode(node, newTitle);

    final trimmed = newTitle.trim();
    final path = ref.read(folderPathProvider);
    if (path.any((n) => n.id == node.id)) {
      ref.read(folderPathProvider.notifier).state = path
          .map((n) => n.id == node.id ? n.copyWith(title: trimmed) : n)
          .toList();
    }

    if (node.type == NodeType.note) {
      final tabs = ref.read(openedTabsProvider);
      if (tabs.any((t) => t.id == node.id)) {
        final ephemeral = ref.read(ephemeralNoteIdsProvider);
        ref.read(openedTabsProvider.notifier).state = tabs
            .map(
              (t) => t.id == node.id
                  ? OpenedTab(
                      id: t.id,
                      title: trimmed,
                      accent: t.accent,
                      groupId: t.groupId,
                      isEphemeral: ephemeral.contains(t.id),
                    )
                  : t,
            )
            .toList();
      }
    }
  }

  Future<void> _moveNode(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
  ) async {
    final folders = await ref.read(homeRepositoryProvider).getAllFolders();
    if (!context.mounted) return;
    final dest = await showScrapDialog<String>(
      context: context,
      builder: (ctx) => _MoveToPileDialog(
        node: node,
        folders: folders,
        currentParentId: node.parentId,
      ),
    );
    if (dest == null || !mounted) return;
    final ok = await ref.read(currentHomeNodesProvider.notifier).moveNode(
          node.id,
          dest,
        );
    if (!context.mounted) return;
    if (ok) {
      showPaperToast(
        context,
        dest == 'root' ? 'Moved to the desk' : 'Moved to pile',
      );
    } else {
      showPaperToast(context, 'Couldn\'t move into that pile');
    }
  }

  Future<void> _tearOutScrap(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
  ) async {
    if (node.type != NodeType.note) return;
    ScrapFeedback.action();
    try {
      await shareScrapPng(ref, node);
    } catch (e) {
      debugPrint('Tear out failed: $e');
      if (!context.mounted) return;
      showPaperToast(
        context,
        isSharePluginMissing(e)
            ? 'Stop and restart the app to enable Tear out'
            : 'Couldn\'t tear out this scrap',
      );
    }
  }

  Future<void> _toggleStar(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
  ) async {
    if (!node.isFile) return;
    ScrapFeedback.tap();
    await ref.read(currentHomeNodesProvider.notifier).toggleStarred(node);
    if (!context.mounted) return;
    showPaperToast(
      context,
      node.starred ? 'Removed from Saved' : 'Pinned to Saved',
    );
  }

  Widget _cardHeader(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
    String typeLabel,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ScrapStampLabel(
            text: typeLabel,
            color: node.type == NodeType.folder
                ? ScrapTheme.accent
                : ScrapTheme.mutedText,
          ),
        ),
        _cardHeaderActions(context, ref, node),
      ],
    );
  }

  Widget _cardHeaderActions(
    BuildContext context,
    WidgetRef ref,
    HomeNode node,
  ) {
    final inTrash = ref.read(currentFolderIdProvider) == trashFolderId;

    if (inTrash) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Restore',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _restoreNode(context, ref, node),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.restore_outlined,
                  color: ScrapTheme.mutedText,
                  size: 20,
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Crush forever',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _permanentlyCrushNode(context, ref, node),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.delete_forever_outlined,
                  color: ScrapTheme.inkRed,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (node.isFile)
          Tooltip(
            message: node.starred ? 'Remove from Saved' : 'Save',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleStar(context, ref, node),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  node.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: node.starred
                      ? ScrapTheme.accent
                      : ScrapTheme.mutedText,
                  size: 20,
                ),
              ),
            ),
          ),
        Tooltip(
          message: 'Crush',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _crushNode(context, ref, node),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.delete_outline,
                color: ScrapTheme.mutedText,
                size: 20,
              ),
            ),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(
            Icons.more_horiz,
            color: ScrapTheme.mutedText,
            size: 20,
          ),
          tooltip: 'Options',
          elevation: 1,
          color: ScrapTheme.cardSurface,
          onSelected: (val) {
            if (val == 'rename') {
              _renameNode(context, ref, node);
            } else if (val == 'move') {
              _moveNode(context, ref, node);
            } else if (val == 'tear') {
              _tearOutScrap(context, ref, node);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'rename',
              child: Text('Rename'),
            ),
            const PopupMenuItem(
              value: 'move',
              child: Text('Move to pile…'),
            ),
            if (node.type == NodeType.note)
              const PopupMenuItem(
                value: 'tear',
                child: Text('Tear out'),
              ),
          ],
        ),
      ],
    );
  }
}

class _RenameNodeDialog extends StatefulWidget {
  final String initialTitle;
  final String dialogTitle;

  const _RenameNodeDialog({
    required this.initialTitle,
    this.dialogTitle = 'Rename',
  });

  @override
  State<_RenameNodeDialog> createState() => _RenameNodeDialogState();
}

class _RenameNodeDialogState extends State<_RenameNodeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ScrapTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      title: Text(
        widget.dialogTitle,
        style: ScrapTextStyles.heading.copyWith(fontSize: 18),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: ScrapTextStyles.body,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Name',
          filled: true,
          fillColor: ScrapTheme.background,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(ScrapTheme.borderRadiusDefault),
            borderSide: const BorderSide(color: ScrapTheme.dividers),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(ScrapTheme.borderRadiusDefault),
            borderSide: const BorderSide(
              color: ScrapTheme.accent,
              width: 1.5,
            ),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.mutedText),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            'Rename',
            style: ScrapTextStyles.body.copyWith(
              color: ScrapTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Minimal stacked-sheet glyph for pile cards.
class _PileStackGraphic extends StatelessWidget {
  final bool compact;

  const _PileStackGraphic({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final w = compact ? 40.0 : 72.0;
    final h = compact ? 32.0 : 56.0;
    final sheetW = compact ? 30.0 : 52.0;
    final sheetH = compact ? 22.0 : 40.0;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned(
            left: compact ? 6 : 10,
            top: 0,
            child: _sheet(
              color: ScrapTheme.kraft,
              width: sheetW,
              height: sheetH,
              compact: compact,
            ),
          ),
          Positioned(
            left: compact ? 3 : 5,
            top: compact ? 4 : 6,
            child: _sheet(
              color: ScrapTheme.tape,
              width: sheetW,
              height: sheetH,
              compact: compact,
            ),
          ),
          Positioned(
            left: 0,
            top: compact ? 8 : 12,
            child: _sheet(
              color: ScrapTheme.cardSurface,
              width: sheetW,
              height: sheetH,
              border: true,
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheet({
    required Color color,
    required double width,
    required double height,
    bool border = false,
    bool compact = false,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusSmall),
        border: border
            ? Border.all(color: ScrapTheme.dividers, width: 1)
            : null,
      ),
      padding: compact
          ? const EdgeInsets.fromLTRB(5, 5, 5, 4)
          : const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: border
          ? Column(
              children: [
                Container(height: compact ? 1.5 : 2, color: ScrapTheme.notebookLines),
                SizedBox(height: compact ? 3 : 5),
                Container(height: compact ? 1.5 : 2, color: ScrapTheme.notebookLines),
                if (!compact) ...[
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 22,
                      height: 2,
                      color: ScrapTheme.notebookLines,
                    ),
                  ),
                ],
              ],
            )
          : null,
    );
  }
}

/// Perforated kraft rule between the piles strip and the files grid.
class _PilesSectionDivider extends StatelessWidget {
  const _PilesSectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      child: Row(
        children: [
          const Expanded(child: _PerforationDivider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '⟨ Scraps ⟩',
              style: ScrapTextStyles.label.copyWith(
                color: ScrapTheme.accent,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const Expanded(child: _PerforationDivider()),
        ],
      ),
    );
  }
}

/// Empty paper slot left on the desk while a scrap is lifted.
class _DeskSlotGhost extends StatelessWidget {
  const _DeskSlotGhost();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ScrapTheme.kraft.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        border: Border.all(color: ScrapTheme.dividers, width: 1),
      ),
    );
  }
}

/// Proportionally scaled-down replica of a desk card, following the pointer.
class _MinimizedDragFeedback extends StatelessWidget {
  final HomeNode node;

  const _MinimizedDragFeedback({required this.node});

  static const double _fileWidth = 168;
  static const double _fileHeight = 152;
  static const double _pileWidth = 200;
  static const double _pileHeight = 64;

  @override
  Widget build(BuildContext context) {
    final isFolder = node.type == NodeType.folder;
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: IgnorePointer(
        child: isFolder ? _miniPile() : _miniFile(),
      ),
    );
  }

  Widget _miniFile() {
    final isScrap = node.type == NodeType.note;
    final hasPreview = isScrap || node.isPdf;
    final typeLabel = isScrap ? '⟨ Scrap ⟩' : '⟨ Document ⟩';

    return Container(
      width: _fileWidth,
      height: _fileHeight,
      decoration: BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        boxShadow: ScrapTheme.deskShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPreview)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ScrapTheme.background,
                    borderRadius:
                        BorderRadius.circular(ScrapTheme.borderRadiusSmall),
                    boxShadow: ScrapTheme.subtleShadow,
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(ScrapTheme.borderRadiusSmall),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: isScrap
                              ? ScrapThumbnail(noteId: node.id)
                              : PdfThumbnail(nodeId: node.id),
                        ),
                        Positioned(
                          top: 6,
                          left: 8,
                          child: ScrapStampLabel(
                            text: typeLabel,
                            color: ScrapTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: ScrapStampLabel(
                text: typeLabel,
                color: ScrapTheme.mutedText,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Text(
              node.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ScrapTextStyles.heading.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniPile() {
    final seed = node.id.hashCode;
    return SizedBox(
      width: _pileWidth,
      height: _pileHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 5,
            left: 5,
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: ((seed % 7) - 3) * 0.012,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ScrapTheme.kraft,
                  borderRadius:
                      BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            left: 2,
            right: 2,
            bottom: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ScrapTheme.tape,
                borderRadius:
                    BorderRadius.circular(ScrapTheme.borderRadiusDefault),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: ScrapTheme.accentSurface,
                borderRadius:
                    BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                border: Border.all(
                  color: ScrapTheme.accent.withValues(alpha: 0.18),
                  width: 1,
                ),
                boxShadow: ScrapTheme.deskShadow,
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  const _PileStackGraphic(compact: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const ScrapStampLabel(
                          text: '⟨ Pile ⟩',
                          color: ScrapTheme.accent,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          node.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ScrapTextStyles.heading.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewScrapButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLooseTap;
  final bool compact;

  const _NewScrapButton({
    required this.onTap,
    required this.onLooseTap,
    this.compact = false,
  });

  @override
  State<_NewScrapButton> createState() => _NewScrapButtonState();
}

class _NewScrapButtonState extends State<_NewScrapButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _looseHovered = false;
  bool _loosePressed = false;

  @override
  Widget build(BuildContext context) {
    final lift = _pressed ? 0.0 : (_hovered ? -2.0 : 0.0);
    final compact = widget.compact;

    return AnimatedContainer(
      duration: ScrapMotion.press,
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, lift, 0),
      width: double.infinity,
      decoration: BoxDecoration(
        color: _hovered
            ? const Color(0xFFFAF8F5)
            : ScrapTheme.cardSurface,
        borderRadius:
            BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        border: Border.all(
          color: _hovered
              ? ScrapTheme.accent.withValues(alpha: 0.35)
              : ScrapTheme.dividers,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(_hovered ? 0x0C000000 : 0x06000000),
            offset: Offset(0, _hovered ? 8 : 4),
            blurRadius: _hovered ? 20 : 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Primary: filed scrap
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() {
              _hovered = false;
              _pressed = false;
            }),
            child: GestureDetector(
              key: SmeltGuideKeys.newScrapButton,
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 32,
                  vertical: compact ? 16 : 28,
                ),
                child: Row(
                  children: [
                    // Blank scrap glyph
                    SizedBox(
                      width: compact ? 40 : 56,
                      height: compact ? 48 : 68,
                      child: FittedBox(
                        child: SizedBox(
                      width: 56,
                      height: 68,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 6,
                            top: 4,
                            child: Transform.rotate(
                              angle: 0.06,
                              child: Container(
                                width: 44,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: ScrapTheme.dividers,
                                  borderRadius: BorderRadius.circular(
                                    ScrapTheme.borderRadiusSmall,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            child: Transform.rotate(
                              angle: -0.03,
                              child: Container(
                                width: 44,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: ScrapTheme.background,
                                  borderRadius: BorderRadius.circular(
                                    ScrapTheme.borderRadiusSmall,
                                  ),
                                  border: Border.all(
                                    color: ScrapTheme.accent
                                        .withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                padding:
                                    const EdgeInsets.fromLTRB(8, 12, 8, 8),
                                child: Column(
                                  children: [
                                    Container(
                                      height: 2,
                                      color: ScrapTheme.notebookLines,
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 2,
                                      color: ScrapTheme.notebookLines,
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width: 16,
                                        height: 2,
                                        color: ScrapTheme.notebookLines,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                      ),
                    ),
                    SizedBox(width: compact ? 16 : 28),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ScrapStampLabel(
                            text: '⟨ Fresh sheet ⟩',
                            color: ScrapTheme.accent,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'New Scrap',
                            style: ScrapTextStyles.heading.copyWith(
                              fontSize: compact ? 20 : 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!compact) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Grab a blank scrap and start scribbling',
                            style: ScrapTextStyles.caption.copyWith(
                              color: ScrapTheme.mutedText,
                            ),
                          ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '+',
                      style: ScrapTextStyles.heading.copyWith(
                        fontSize: compact ? 28 : 36,
                        color: ScrapTheme.accent.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Perforation — tear-off edge for a loose scrap
          const _PerforationDivider(),

          // Secondary: ephemeral loose scrap
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _looseHovered = true),
            onExit: (_) => setState(() {
              _looseHovered = false;
              _loosePressed = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _loosePressed = true),
              onTapUp: (_) => setState(() => _loosePressed = false),
              onTapCancel: () => setState(() => _loosePressed = false),
              onTap: widget.onLooseTap,
              child: AnimatedContainer(
                duration: ScrapMotion.press,
                curve: Curves.easeOut,
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 32,
                  compact ? 10 : 14,
                  compact ? 16 : 28,
                  compact ? 12 : 16,
                ),
                decoration: BoxDecoration(
                  color: _loosePressed
                      ? ScrapTheme.pressedSurface
                      : (_looseHovered
                          ? ScrapTheme.kraft.withValues(alpha: 0.28)
                          : ScrapTheme.codeSurface.withValues(alpha: 0.55)),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(ScrapTheme.borderRadiusDefault - 1),
                  ),
                ),
                child: Row(
                  children: [
                    // Slightly askew torn scrap glyph
                    Transform.rotate(
                      angle: -0.08,
                      child: CustomPaint(
                        size: const Size(22, 28),
                        painter: _LooseScrapGlyphPainter(
                          ink: ScrapTheme.mutedText.withValues(
                            alpha: _looseHovered ? 0.85 : 0.55,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ScrapStampLabel(
                            text: '⟨ won\'t be filed ⟩',
                            color: ScrapTheme.mutedText,
                            tiltDegrees: 1.5,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Loose scrap',
                            style: ScrapTextStyles.body.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ScrapTheme.secondaryText,
                            ),
                          ),
                          if (!compact) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Scribble freely — vanishes when you leave',
                            style: ScrapTextStyles.caption.copyWith(
                              fontSize: 12,
                              color: ScrapTheme.mutedText,
                            ),
                          ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '~',
                      style: ScrapTextStyles.heading.copyWith(
                        fontSize: 26,
                        color: ScrapTheme.mutedText.withValues(
                          alpha: _looseHovered ? 0.85 : 0.55,
                        ),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed tear-line between the filed scrap and the loose tear-off.
class _PerforationDivider extends StatelessWidget {
  const _PerforationDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: CustomPaint(
        painter: _PerforationPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ScrapTheme.kraft.withValues(alpha: 0.9)
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    const dash = 3.0;
    const gap = 4.5;
    final y = size.height / 2;
    var x = 20.0;
    while (x < size.width - 20) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }

    // Punch holes along the tear
    final hole = Paint()..color = ScrapTheme.dividers;
    x = 28.0;
    while (x < size.width - 28) {
      canvas.drawCircle(Offset(x, y), 1.4, hole);
      x += 18;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LooseScrapGlyphPainter extends CustomPainter {
  final Color ink;

  _LooseScrapGlyphPainter({required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(2, 1)
      ..lineTo(size.width - 1, 2)
      ..lineTo(size.width - 3, size.height - 1)
      ..lineTo(1, size.height - 3)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = ScrapTheme.background
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    // Short scribble lines
    final line = Paint()
      ..color = ink.withValues(alpha: 0.45)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(5, size.height * 0.35),
      Offset(size.width - 6, size.height * 0.38),
      line,
    );
    canvas.drawLine(
      Offset(5, size.height * 0.55),
      Offset(size.width - 9, size.height * 0.52),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _LooseScrapGlyphPainter oldDelegate) =>
      oldDelegate.ink != ink;
}

class _ApiKeyBanner extends StatelessWidget {
  final VoidCallback onSetup;
  final VoidCallback onDismiss;

  const _ApiKeyBanner({
    required this.onSetup,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: ScrapTheme.accentSurface,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⟨ Gemini ⟩',
                  style: ScrapTextStyles.label.copyWith(
                    color: ScrapTheme.accent,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add your Gemini API key to use Smelt',
                  style: ScrapTextStyles.body.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          PaperButton(
            label: 'Set up',
            variant: PaperButtonVariant.primary,
            compact: true,
            onPressed: onSetup,
          ),
          PaperIconButton(
            icon: Icons.close,
            tooltip: 'Dismiss',
            color: ScrapTheme.mutedText,
            iconSize: 18,
            size: 32,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _MoveToPileDialog extends StatelessWidget {
  final HomeNode node;
  final List<HomeNode> folders;
  final String currentParentId;

  const _MoveToPileDialog({
    required this.node,
    required this.folders,
    required this.currentParentId,
  });

  int _depth(HomeNode folder, Map<String, HomeNode> byId) {
    var d = 0;
    var walk = folder.parentId;
    final seen = <String>{folder.id};
    while (walk != 'root' && byId.containsKey(walk) && seen.add(walk)) {
      d++;
      walk = byId[walk]!.parentId;
      if (d > 8) break;
    }
    return d;
  }

  bool _isSelfOrDescendant(HomeNode folder, Map<String, HomeNode> byId) {
    if (node.type != NodeType.folder) return folder.id == node.id;
    var walk = folder.id;
    final seen = <String>{};
    while (walk != 'root' && seen.add(walk)) {
      if (walk == node.id) return true;
      walk = byId[walk]?.parentId ?? 'root';
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final f in folders) f.id: f};
    final options = folders
        .where((f) => !_isSelfOrDescendant(f, byId))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return AlertDialog(
      backgroundColor: ScrapTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      title: Text(
        'Move to pile',
        style: ScrapTextStyles.heading.copyWith(fontSize: 18),
      ),
      content: SizedBox(
        width: math.min(360, MediaQuery.sizeOf(context).width - 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pileChoice(
                context,
                label: 'Desk',
                selected: currentParentId == 'root',
                indent: 0,
                onTap: () => Navigator.pop(context, 'root'),
              ),
              for (final folder in options)
                _pileChoice(
                  context,
                  label: folder.title,
                  selected: currentParentId == folder.id,
                  indent: _depth(folder, byId),
                  onTap: () => Navigator.pop(context, folder.id),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.mutedText),
          ),
        ),
      ],
    );
  }

  Widget _pileChoice(
    BuildContext context, {
    required String label,
    required bool selected,
    required int indent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8.0 + indent * 16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check : Icons.folder_outlined,
              size: 18,
              color: selected ? ScrapTheme.accent : ScrapTheme.mutedText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: ScrapTextStyles.body.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? ScrapTheme.accent : ScrapTheme.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
