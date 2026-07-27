import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/widgets/scrap_tilt.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
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
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/api_key_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _bannerDismissed = false;
  String? _lastWarmedFolderKey;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'API key saved',
              style: ScrapTextStyles.body.copyWith(color: Colors.white),
            ),
            backgroundColor: ScrapTheme.accent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openApiKeyDialog() async {
    final saved = await showApiKeyDialog(context, allowSkip: true);
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'API key saved',
            style: ScrapTextStyles.body.copyWith(color: Colors.white),
          ),
          backgroundColor: ScrapTheme.accent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _createAndOpenScrap() async {
    final node = await ref
        .read(currentHomeNodesProvider.notifier)
        .createNote('Untitled Scrap');
    if (!mounted) return;
    ref.read(activeNoteIdProvider.notifier).state = node.id;
    openNoteTab(ref, node.id, node.title);
    context.push('/note_editor').then((_) {
      invalidateNoteThumbnail(ref, node.id);
    });
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
                      GestureDetector(
                        onTap: () => ref
                            .read(currentHomeNodesProvider.notifier)
                            .createFolder('New Folder'),
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
                      GestureDetector(
                        onTap: _createAndOpenScrap,
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
                      GestureDetector(
                        onTap: () => ref
                            .read(currentHomeNodesProvider.notifier)
                            .importDocument(),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showBanner) ...[
                      _ApiKeyBanner(
                        onSetup: _openApiKeyDialog,
                        onDismiss: () =>
                            setState(() => _bannerDismissed = true),
                      ),
                      const SizedBox(height: 24),
                    ],

                    _NewScrapButton(onTap: _createAndOpenScrap),
                    const SizedBox(height: 40),

                    // Breadcrumb Navigation
                    Row(
                      children: [
                        if (currentFolder != 'root') ...[
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: ScrapTheme.primaryText,
                            ),
                            onPressed: () {
                              final path = ref.read(folderPathProvider);
                              if (path.length > 1) {
                                ref
                                    .read(currentFolderIdProvider.notifier)
                                    .state = path[path.length - 2].id;
                                ref.read(folderPathProvider.notifier).state =
                                    path.sublist(0, path.length - 1);
                              } else {
                                ref
                                    .read(currentFolderIdProvider.notifier)
                                    .state = 'root';
                                ref.read(folderPathProvider.notifier).state =
                                    [];
                              }
                            },
                          ),
                          const SizedBox(width: 16),
                        ],
                        AnimatedSwitcher(
                          duration: ScrapMotion.panel,
                          switchInCurve: ScrapMotion.panelCurve,
                          switchOutCurve: ScrapMotion.panelCurve,
                          transitionBuilder: (child, animation) {
                            return SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.12),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            );
                          },
                          child: Text(
                            currentFolder == 'root'
                                ? 'All Files'
                                : folderPath.last.title,
                            key: ValueKey(currentFolder),
                            style: ScrapTextStyles.heading
                                .copyWith(fontSize: 24),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Grid View of Nodes — remount on folder change so
                    // cards get a brief staggered scrap entrance.
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey(currentFolder),
                        child: nodesAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                              color: ScrapTheme.accent,
                            ),
                          ),
                          error: (err, stack) =>
                              Center(child: Text('Error: $err')),
                          data: (nodes) {
                            if (nodes.isEmpty) {
                              return Center(
                                child: Text(
                                  'Empty folder. Grab a scrap above, or import a doc.',
                                  style: ScrapTextStyles.caption.copyWith(
                                    color: ScrapTheme.mutedText,
                                  ),
                                ),
                              );
                            }

                            return GridView.builder(
                              cacheExtent: 800,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 32,
                                mainAxisSpacing: 32,
                                childAspectRatio: 1.1,
                              ),
                              itemCount: nodes.length,
                              itemBuilder: (context, index) {
                                final node = nodes[index];
                                return ScrapCardEntrance(
                                  index: index,
                                  stagger:
                                      const Duration(milliseconds: 28),
                                  child: RepaintBoundary(
                                    child: ScrapTilt(
                                      key: ValueKey(node.id),
                                      seed: node.id.hashCode,
                                      child: _buildNodeCard(
                                          context, ref, node),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
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

  Widget _buildNodeCard(BuildContext context, WidgetRef ref, HomeNode node) {
    return _ScrapPressable(
      onTap: () {
        if (node.type == NodeType.folder) {
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
          context.push('/note_editor').then((_) {
            invalidateNoteThumbnail(ref, node.id);
          });
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
            if (val == 'delete') {
              ref.read(currentHomeNodesProvider.notifier).deleteNode(node.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Text(
                'Crush',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
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

class _ScrapPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _ScrapPressable({
    required this.child,
    required this.onTap,
  });

  @override
  State<_ScrapPressable> createState() => _ScrapPressableState();
}

class _ScrapPressableState extends State<_ScrapPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: ScrapMotion.press,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class _NewScrapButton extends StatefulWidget {
  final VoidCallback onTap;

  const _NewScrapButton({required this.onTap});

  @override
  State<_NewScrapButton> createState() => _NewScrapButtonState();
}

class _NewScrapButtonState extends State<_NewScrapButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final lift = _pressed ? 0.0 : (_hovered ? -2.0 : 0.0);

    return MouseRegion(
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
        child: AnimatedContainer(
          duration: ScrapMotion.press,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, lift, 0),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
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
                              color: ScrapTheme.accent.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
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
    );
  }
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
          TextButton(
            onPressed: onSetup,
            child: Text(
              'Set up',
              style: ScrapTextStyles.body.copyWith(
                color: ScrapTheme.accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(
              Icons.close,
              size: 18,
              color: ScrapTheme.mutedText,
            ),
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
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: AnimatedContainer(
        duration: ScrapMotion.panel,
        curve: ScrapMotion.panelCurve,
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected
              ? ScrapTheme.accent.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          children: [
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
