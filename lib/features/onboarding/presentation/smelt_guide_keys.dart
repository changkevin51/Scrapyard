import 'package:flutter/material.dart';

/// GlobalKeys for coach-tour spotlights. Attached to existing widgets.
class SmeltGuideKeys {
  SmeltGuideKeys._();

  static final newScrapButton = GlobalKey(debugLabel: 'guide_new_scrap');
  static final smeltTool = GlobalKey(debugLabel: 'guide_smelt_tool');
  static final smeltPill = GlobalKey(debugLabel: 'guide_smelt_pill');
  static final smeltCodePill = GlobalKey(debugLabel: 'guide_smelt_code_pill');
  static final smeltAnswer = GlobalKey(debugLabel: 'guide_smelt_answer');
  static final showSteps = GlobalKey(debugLabel: 'guide_show_steps');
  static final askNext = GlobalKey(debugLabel: 'guide_ask_next');
  static final continueInChat = GlobalKey(debugLabel: 'guide_continue_chat');
  static final chatSelect = GlobalKey(debugLabel: 'guide_chat_select');

  static Rect? rectOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  static Rect? unionOf(List<GlobalKey> keys) {
    Rect? acc;
    for (final key in keys) {
      final r = rectOf(key);
      if (r == null) continue;
      acc = acc == null ? r : acc.expandToInclude(r);
    }
    return acc;
  }
}
