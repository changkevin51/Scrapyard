import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
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
import '../providers/home_providers.dart' show
    currentFolderIdProvider,
    currentHomeNodesProvider,
    folderPathProvider,
    invalidateNoteThumbnail,
    scrapThumbnailPreloaderProvider;
import '../widgets/scrap_thumbnail.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../../canvas/presentation/widgets/pending_scrap_flow.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/api_key_dialog.dart';
import '../../../splash/presentation/providers/splash_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _bannerDismissed = false;
  String? _lastWarmedFolderKey;
  final Map<String, GlobalKey> _crushKeys = {};

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
    ref.read(apiKeySetupPromptedProvider.notifier).state = true;

    final key = keyState.valueOrNull;
    if (key == null || key.isEmpty) {
      final saved = await showApiKeyDialog(context, allowSkip: true);
      if (saved == true && mounted) {
        showPaperToast(context, 'API key saved');
      }
    }
  }

  Future<void> _openApiKeyDialog() async {
    final saved = await showApiKeyDialog(context, allowSkip: true);
    if (saved == true && mounted) {
      showPaperToast(context, 'API key saved');
    }
  }

  Future<void> _createAndOpenScrap() async {
    final folderId = ref.read(currentFolderIdProvider);
    final node = HomeNode.create(
      title: 'New scrap',
      type: NodeType.note,
      parentId: folderId,
    );
    if (!mounted) return;
    ref.read(pendingNewScrapsProvider.notifier).update((m) => {...m, node.id: node});
    ref.read(activeNoteIdProvider.notifier).state = node.id;
    openNoteTab(ref, node.id, node.title, ephemeral: true);
    context.push('/note_editor').then((_) => _onNoteEditorClosed(node.id));
  }

  void _openLooseScrap() {
    ScrapFeedback.action();
    final id = 'loose-${DateTime.now().microsecondsSinceEpoch}';
    openNoteTab(ref, id, 'Loose scrap', ephemeral: true);
    context.push('/note_editor').then((_) {
      final hadLoose = ref.read(ephemeralNoteIdsProvider).isNotEmpty;
      discardAllEphemeralNotes(ref);
      ref.read(dirtyNoteIdsProvider.notifier).state = {};
      if (hadLoose && mounted) {
        showPaperToast(context, 'Loose scrap drifted off');
      }
    });
  }

  /// Refresh home timestamps/thumbnails after canvas edits.
  Future<void> _onNoteEditorClosed(String noteId) async {
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
    ref.read(pendingNewScrapsProvider.notifier).state = {};
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

    return Scaffold(
      // Keep the sidebar layout stable while modal dialogs (e.g. API key) are open.
      resizeToAvoidBottomInset: false,
      body: Row(
        children: [
          // Left Sidebar
          Container(
            width: 232,
            decoration: const BoxDecoration(
              color: ScrapTheme.background,
              border: Border(
                right: BorderSide(color: ScrapTheme.dividers, width: 1.0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Padding(
                  padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0),
                  child: Image.asset(
                    'assets/images/HomeLogo.png',
                    width: 184,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
             
                ),
                const SizedBox(height: 38),
                _SidebarItem(
                  title: 'Home',
                  isSelected: currentFolder == 'root',
                  onTap: () {
                    ref.read(currentFolderIdProvider.notifier).state = 'root';
                    ref.read(folderPathProvider.notifier).state = [];
                  },
                ),
                _SidebarItem(
                  title: 'Settings',
                  isSelected: false,
                  onTap: () => context.push('/settings'),
                ),
                if (hasApiKey)
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
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScrapPressable(
                        scale: 0.96,
                        onTap: () {
                          ScrapFeedback.tap();
                          ref
                              .read(currentHomeNodesProvider.notifier)
                              .createFolder('New Folder');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            '+  New folder',
                            style: ScrapTextStyles.body.copyWith(
                              color: ScrapTheme.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      ScrapPressable(
                        scale: 0.96,
                        onTap: () {
                          ScrapFeedback.tap();
                          _createAndOpenScrap();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            '+  New scrap',
                            style: ScrapTextStyles.body.copyWith(
                              color: ScrapTheme.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      ScrapPressable(
                        scale: 0.96,
                        onTap: () {
                          ScrapFeedback.tap();
                          _openLooseScrap();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            '~  Loose scrap',
                            style: ScrapTextStyles.body.copyWith(
                              color: ScrapTheme.mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      ScrapPressable(
                        scale: 0.96,
                        onTap: () {
                          ScrapFeedback.tap();
                          ref
                              .read(currentHomeNodesProvider.notifier)
                              .importDocument();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            '↑  Import app/doc',
                            style: ScrapTextStyles.body.copyWith(
                              color: ScrapTheme.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: ColoredBox(
              color: ScrapTheme.background,
              child: Padding(
                padding: const EdgeInsets.all(48.0),
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
                    SliverToBoxAdapter(
                      child: _NewScrapButton(
                        onTap: _createAndOpenScrap,
                        onLooseTap: _openLooseScrap,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),

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
                              offset: currentFolder == 'root'
                                  ? const Offset(-0.35, 0)
                                  : Offset.zero,
                              child: AnimatedOpacity(
                                duration: ScrapMotion.panel,
                                curve: ScrapMotion.panelCurve,
                                opacity:
                                    currentFolder == 'root' ? 0.0 : 1.0,
                                child: IgnorePointer(
                                  ignoring: currentFolder == 'root',
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: ScrapTheme.primaryText,
                                    ),
                                    onPressed: () {
                                      final path =
                                          ref.read(folderPathProvider);
                                      if (path.length > 1) {
                                        ref
                                            .read(currentFolderIdProvider
                                                .notifier)
                                            .state = path[path.length - 2].id;
                                        ref
                                            .read(folderPathProvider.notifier)
                                            .state = path.sublist(
                                                0, path.length - 1);
                                      } else {
                                        ref
                                            .read(currentFolderIdProvider
                                                .notifier)
                                            .state = 'root';
                                        ref
                                            .read(folderPathProvider.notifier)
                                            .state = [];
                                      }
                                    },
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
                                currentFolder == 'root'
                                    ? 'All Files'
                                    : folderPath.last.title,
                                key: ValueKey(currentFolder),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ScrapTextStyles.heading
                                    .copyWith(fontSize: 24),
                              ),
                            ),
                          ),
                        ],
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
                            child: Center(child: Text('Error: $err')),
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
                                    'Empty folder. Grab a scrap above, or import a doc.',
                                    style: ScrapTextStyles.caption.copyWith(
                                      color: ScrapTheme.mutedText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ];
                        }

                        return [
                          SliverGrid(
                            key: ValueKey(currentFolder),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 32,
                              mainAxisSpacing: 32,
                              childAspectRatio: 1.1,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final node = nodes[index];
                                return ScrapCardEntrance(
                                  index: index,
                                  stagger:
                                      const Duration(milliseconds: 28),
                                  child: RepaintBoundary(
                                    key: _crushKeys.putIfAbsent(
                                        node.id, GlobalKey.new),
                                    child: ScrapTilt(
                                      key: ValueKey(node.id),
                                      seed: node.id.hashCode,
                                      child: _buildNodeCard(
                                          context, ref, node),
                                    ),
                                  ),
                                );
                              },
                              childCount: nodes.length,
                            ),
                          ),
                        ];
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(BuildContext context, WidgetRef ref, HomeNode node) {
    return ScrapPressable(
      onTap: () {
        if (node.type == NodeType.folder) {
          ScrapFeedback.action();
          ref.read(currentFolderIdProvider.notifier).state = node.id;
          ref.read(folderPathProvider.notifier).state = [
            ...ref.read(folderPathProvider),
            node,
          ];
        } else if (node.type == NodeType.document) {
          if (node.externalPath != null &&
              node.externalPath!.endsWith('.pdf')) {
            context.push('/pdf_viewer');
          } else if (node.externalPath != null) {
            OpenFilex.open(node.externalPath!);
          }
        } else if (node.type == NodeType.note) {
          // Set the active note ID BEFORE navigating so the editor
          // loads this specific note's strokes.
          ref.read(activeNoteIdProvider.notifier).state = node.id;
          openNoteTab(ref, node.id, node.title);
          context.push('/note_editor').then((_) => _onNoteEditorClosed(node.id));
        }
      },
      child: node.type == NodeType.folder
          ? _buildPileCard(context, ref, node)
          : _buildFlatCard(context, ref, node),
    );
  }

  /// Scrap / document card — single flat sheet.
  Widget _buildFlatCard(BuildContext context, WidgetRef ref, HomeNode node) {
    final isScrap = node.type == NodeType.note;
    final typeLabel = isScrap ? '⟨ Scrap ⟩' : '⟨ Document ⟩';

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
          if (isScrap)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                          child: ScrapThumbnail(noteId: node.id),
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
              padding: const EdgeInsets.fromLTRB(28, 28, 16, 0),
              child: _cardHeader(context, ref, node, typeLabel),
            ),
            const Spacer(),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(28, isScrap ? 16 : 0, 28, 28),
            child: _cardMeta(node),
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

  /// Pile card — stacked sheets with a warm folder tab.
  Widget _buildPileCard(BuildContext context, WidgetRef ref, HomeNode node) {
    final seed = node.id.hashCode;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Back sheet — slightly rotated
          Positioned(
            top: 10,
            left: 10,
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
          // Middle sheet
          Positioned(
            top: 5,
            left: 5,
            right: 4,
            bottom: 4,
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
          // Front sheet
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
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    offset: Offset(0, 4),
                    blurRadius: 12,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Folder tab strip
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(left: 24),
                      width: 52,
                      height: 8,
                      decoration: BoxDecoration(
                        color: ScrapTheme.accent.withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                    child: _cardHeader(context, ref, node, '⟨ Pile ⟩'),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _PileStackGraphic(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: _cardMeta(node),
                  ),
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

  Widget _cardMeta(HomeNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          node.title,
          style: ScrapTextStyles.heading.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          _formatNodeUpdatedAt(node.updatedAt),
          style: ScrapTextStyles.caption.copyWith(
            color: ScrapTheme.mutedText,
          ),
        ),
      ],
    );
  }

  /// Snapshot the card and play the crush overlay; the node is deleted as
  /// soon as the snapshot is captured so the grid reflows under the animation.
  void _crushNode(BuildContext context, WidgetRef ref, HomeNode node) {
    ScrapFeedback.warn();
    final key = _crushKeys.remove(node.id);
    ScrapCrush.crush(
      context,
      key,
      onCrushed: () =>
          ref.read(currentHomeNodesProvider.notifier).deleteNode(node.id),
    );
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
        ScrapStampLabel(
          text: typeLabel,
          color: node.type == NodeType.folder
              ? ScrapTheme.accent
              : ScrapTheme.mutedText,
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
            } else if (val == 'delete') {
              _crushNode(context, ref, node);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'rename',
              child: Text('Rename'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text(
                'Crush',
                style: TextStyle(color: ScrapTheme.inkRed),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RenameNodeDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameNodeDialog({required this.initialTitle});

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
        'Rename',
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
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 56,
      child: Stack(
        children: [
          Positioned(
            left: 10,
            top: 0,
            child: _sheet(
              color: ScrapTheme.kraft,
              width: 52,
              height: 40,
            ),
          ),
          Positioned(
            left: 5,
            top: 6,
            child: _sheet(
              color: ScrapTheme.tape,
              width: 52,
              height: 40,
            ),
          ),
          Positioned(
            left: 0,
            top: 12,
            child: _sheet(
              color: ScrapTheme.cardSurface,
              width: 52,
              height: 40,
              border: true,
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
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: border
          ? Column(
              children: [
                Container(height: 2, color: ScrapTheme.notebookLines),
                const SizedBox(height: 5),
                Container(height: 2, color: ScrapTheme.notebookLines),
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
            )
          : null,
    );
  }
}

class _NewScrapButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLooseTap;

  const _NewScrapButton({
    required this.onTap,
    required this.onLooseTap,
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
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                child: Row(
                  children: [
                    // Blank scrap glyph
                    SizedBox(
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
                    const SizedBox(width: 28),
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
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Grab a blank scrap and start scribbling',
                            style: ScrapTextStyles.caption.copyWith(
                              color: ScrapTheme.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '+',
                      style: ScrapTextStyles.heading.copyWith(
                        fontSize: 36,
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
              onTapDown: (_) => setState(() => _loosePressed = true),
              onTapUp: (_) => setState(() => _loosePressed = false),
              onTapCancel: () => setState(() => _loosePressed = false),
              onTap: widget.onLooseTap,
              child: AnimatedContainer(
                duration: ScrapMotion.press,
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(32, 14, 28, 16),
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
                          const SizedBox(height: 2),
                          Text(
                            'Scribble freely — vanishes when you leave',
                            style: ScrapTextStyles.caption.copyWith(
                              fontSize: 12,
                              color: ScrapTheme.mutedText,
                            ),
                          ),
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

class _SidebarItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.title,
    required this.isSelected,
    required this.onTap,
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
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected
              ? ScrapTheme.accent.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: ScrapMotion.panel,
              curve: ScrapMotion.panelCurve,
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? ScrapTheme.accent
                    : Colors.transparent,
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
                fontSize: 15,
              ),
              child: Text(title),
            ),
          ],
        ),
      ),
    );
  }
}
