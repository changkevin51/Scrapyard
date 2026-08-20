import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../home/data/note_artifacts.dart';
import '../../../home/domain/models/home_node.dart';
import '../../../home/presentation/providers/home_providers.dart';
import '../providers/canvas_providers.dart';

/// In-memory new scraps awaiting a name before they are filed to home.
final pendingNewScrapsProvider =
    StateProvider<Map<String, HomeNode>>((ref) => {});

bool isPendingNewScrap(WidgetRef ref, String id) =>
    ref.read(pendingNewScrapsProvider).containsKey(id);

/// Default title for scraps that have not been named yet.
const defaultNewScrapTitle = 'New scrap';

bool isUnnamedScrapTitle(String title) =>
    title.trim().isEmpty || title.trim() == defaultNewScrapTitle;

/// Open a pending new scrap in a new editor tab (name & file later).
void openNewScrapInTab(WidgetRef ref, {String parentId = 'root'}) {
  stashActiveEphemeralCanvas(ref);
  final node = HomeNode.create(
    title: defaultNewScrapTitle,
    type: NodeType.note,
    parentId: parentId,
  );
  ref
      .read(pendingNewScrapsProvider.notifier)
      .update((m) => {...m, node.id: node});
  openNoteTab(ref, node.id, node.title, ephemeral: true);
}

/// Open an ephemeral loose scrap in a new editor tab (never saved to disk).
void openLooseScrapInTab(WidgetRef ref) {
  stashActiveEphemeralCanvas(ref);
  ScrapFeedback.action();
  final id = 'loose-${DateTime.now().microsecondsSinceEpoch}';
  openNoteTab(ref, id, 'Loose scrap', ephemeral: true);
}

/// File a pending scrap under [title] and persist in-memory canvas data.
Future<void> filePendingNewScrap(
  WidgetRef ref,
  String id,
  String title,
) async {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return;

  final meta = ref.read(pendingNewScrapsProvider)[id];
  if (meta == null) return;

  final node = meta.copyWith(title: trimmed, updatedAt: DateTime.now());

  if (ref.read(activeNoteIdProvider) == id) {
    final strokes = ref.read(strokesProvider);
    if (strokes.isNotEmpty) {
      await ref.read(canvasRepositoryProvider).saveStrokes(id, strokes);
    }
    final textNodes = ref.read(canvasTextNodesProvider);
    if (textNodes.isNotEmpty) {
      await ref.read(canvasRepositoryProvider).saveTextNodes(id, textNodes);
    }
    final tables = ref.read(canvasTablesProvider);
    if (tables.isNotEmpty) {
      await ref.read(canvasRepositoryProvider).saveTables(id, tables);
    }
    final pageConfig = ref.read(pageLayoutProvider);
    await ref
        .read(canvasSettingsRepositoryProvider)
        .upsertPageConfig(id, pageConfig);
  } else {
    final cached = ref.read(ephemeralCanvasCacheProvider)[id];
    if (cached != null) {
      if (cached.strokes.isNotEmpty) {
        await ref.read(canvasRepositoryProvider).saveStrokes(id, cached.strokes);
      }
      if (cached.texts.isNotEmpty) {
        await ref.read(canvasRepositoryProvider).saveTextNodes(id, cached.texts);
      }
      if (cached.tables.isNotEmpty) {
        await ref.read(canvasRepositoryProvider).saveTables(id, cached.tables);
      }
    }
  }

  await ref.read(homeRepositoryProvider).insertNode(node);

  // Refresh the visible folder list if it's currently being watched.
  ref.invalidate(currentHomeNodesProvider);

  ref.read(pendingNewScrapsProvider.notifier).update((m) => {...m}..remove(id));
  ref.read(ephemeralNoteIdsProvider.notifier).update((s) => {...s}..remove(id));
  ref.read(ephemeralCanvasCacheProvider.notifier).update((m) => {...m}..remove(id));
  ref.read(dirtyNoteIdsProvider.notifier).update((s) => {...s, id});

  final tabs = ref.read(openedTabsProvider);
  ref.read(openedTabsProvider.notifier).state = tabs
      .map(
        (t) => t.id == id
            ? OpenedTab(
                id: t.id,
                title: trimmed,
                accent: t.accent,
                groupId: t.groupId,
                isEphemeral: false,
              )
            : t,
      )
      .toList();
}

void discardPendingNewScrap(WidgetRef ref, String id) {
  ref.read(pendingNewScrapsProvider.notifier).update((m) => {...m}..remove(id));
  discardEphemeralNote(ref, id);
  unawaited(NoteArtifacts.deleteForNoteId(id));
}

/// Prompt to name or discard a single pending scrap. Returns false if cancelled.
Future<bool> resolvePendingScrapForTab(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  if (!isPendingNewScrap(ref, id)) return true;

  final pendingTitle = ref.read(pendingNewScrapsProvider)[id]?.title;
  final initialTitle =
      pendingTitle != null && !isUnnamedScrapTitle(pendingTitle)
          ? pendingTitle
          : '';

  final result = await showNameNewScrapDialog(context, initialTitle: initialTitle);
  if (result == null) return false;

  if (result.discard) {
    ScrapFeedback.warn();
    discardPendingNewScrap(ref, id);
  } else {
    ScrapFeedback.action();
    await filePendingNewScrap(ref, id, result.title!);
  }
  return true;
}

/// Resolve pending scraps before leaving the editor. Returns false if cancelled.
Future<bool> resolvePendingScrapsBeforeLeaving(
  BuildContext context,
  WidgetRef ref,
) async {
  stashActiveEphemeralCanvas(ref);

  final looseIds = ref
      .read(ephemeralNoteIdsProvider)
      .where((id) => !ref.read(pendingNewScrapsProvider).containsKey(id))
      .toList();
  for (final id in looseIds) {
    if (!scrapIdHasInk(ref, id)) {
      discardEphemeralNote(ref, id);
      continue;
    }
    if (!context.mounted) return false;
    final drift = await showLetSheetDriftDialog(context);
    if (drift == null) return false;
    if (!drift) return false;
    discardEphemeralNote(ref, id);
  }

  final pending = Map<String, HomeNode>.from(ref.read(pendingNewScrapsProvider));
  if (pending.isEmpty) return true;

  for (final id in pending.keys) {
    if (!scrapIdHasInk(ref, id)) {
      discardPendingNewScrap(ref, id);
      continue;
    }
    if (!context.mounted) return false;
    final resolved = await resolvePendingScrapForTab(context, ref, id);
    if (!resolved) return false;
  }
  return true;
}

/// Leave the note editor after resolving pending scraps.
///
/// Discarding the last tab empties [openedTabsProvider], and
/// [NoteEditorScreen] already pops via that listener — popping again here
/// would remove home and leave a blank navigator stack.
Future<void> leaveNoteEditorIfAllowed(
  BuildContext context,
  WidgetRef ref,
) async {
  final canLeave = await resolvePendingScrapsBeforeLeaving(context, ref);
  if (!canLeave || !context.mounted) return;
  if (ref.read(openedTabsProvider).isEmpty) return;
  Navigator.of(context).pop();
}

// ── Dialog ──────────────────────────────────────────────────────

class NameNewScrapDialogResult {
  final bool discard;
  final String? title;

  const NameNewScrapDialogResult.file(this.title) : discard = false;
  const NameNewScrapDialogResult.discard() : discard = true, title = null;
}

Future<NameNewScrapDialogResult?> showNameNewScrapDialog(
  BuildContext context, {
  String initialTitle = '',
}) {
  return showScrapDialog<NameNewScrapDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _NameNewScrapDialog(initialTitle: initialTitle),
  );
}

class _NameNewScrapDialog extends StatefulWidget {
  final String initialTitle;

  const _NameNewScrapDialog({this.initialTitle = ''});

  @override
  State<_NameNewScrapDialog> createState() => _NameNewScrapDialogState();
}

class _NameNewScrapDialogState extends State<_NameNewScrapDialog> {
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

  void _file() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, NameNewScrapDialogResult.file(trimmed));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: ScrapTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      title: Text(
        'Name your scrap',
        style: ScrapTextStyles.heading.copyWith(fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Give this sheet a name to file it, or discard it.',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.secondaryText),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: ScrapTextStyles.body,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Scrap name',
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
            onSubmitted: (_) => _file(),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, const NameNewScrapDialogResult.discard()),
          child: Text(
            'Discard',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.inkRed),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.mutedText),
          ),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty ? null : _file,
          child: Text(
            'Save',
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

Future<bool?> showLetSheetDriftDialog(BuildContext context) {
  return showScrapDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: ScrapTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      title: Text(
        'Let this sheet drift?',
        style: ScrapTextStyles.heading.copyWith(fontSize: 18),
      ),
      content: Text(
        'This loose scrap won\'t be filed. Drift it off the desk, or keep writing.',
        style: ScrapTextStyles.body.copyWith(color: ScrapTheme.secondaryText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Keep writing',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.mutedText),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Let it drift',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.inkRed),
          ),
        ),
      ],
    ),
  );
}
