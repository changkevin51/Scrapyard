import 'package:flutter/material.dart';

import '../../ai_chat/domain/models/gemini_model.dart';

/// Custom marks that match live UI (not a generic Material stand-in).
enum GuideGlyph { spark, highlighter, eraser, lasso }

/// Hub + topic copy for the in-app Guide. Keep strings here, not in widgets.
class GuideSection {
  final String id;
  final String title;
  final String subtitle;
  final String stamp;
  final IconData? icon;
  final GuideGlyph? glyph;
  final List<GuideTip> tips;
  final bool showToolStrip;
  final bool showModelChart;

  const GuideSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.stamp,
    this.icon,
    this.glyph,
    required this.tips,
    this.showToolStrip = false,
    this.showModelChart = false,
  });

  static const smelt = GuideSection(
    id: 'smelt',
    title: 'Smelt',
    subtitle: 'Circle a problem, get a walkthrough.',
    stamp: '⟨ smelt ⟩',
    icon: Icons.auto_awesome,
    tips: [
      GuideTip(
        icon: Icons.auto_awesome,
        title: 'What Smelt does',
        body:
            'Smelt sends the scraps you select to Google Gemini, using your own API key. Scribble a problem, select it, and the app works through it with you. You get the answer and a step-by-step solution.',
      ),
      GuideTip(
        icon: Icons.touch_app_outlined,
        title: 'Tap your expression, or drag a box',
        body:
            'With Smelt selected, tap near your writing and the app highlights a cluster of strokes. If the box did not capture the complete expression, drag a rectangle instead. After you correct it once, that same expression stays tappable for the rest of the session.',
      ),
      GuideTip(
        icon: Icons.code,
        title: 'Smelt vs Smelt + code',
        body:
            '⟨ Smelt ⟩ walks through the problem. Smelt + code asks Gemini to check the work with code when that helps. Useful for the more complex arithmetic you want verified, not just explained.',
      ),
      GuideTip(
        icon: Icons.expand_more,
        title: 'Show steps and Ask',
        body:
            'The card starts with the answer. Tap Show steps when you want the working. Ask-next chips pick up from there. Continue in Ask if the thread is going to run long.',
      ),
      GuideTip(
        icon: Icons.content_paste,
        title: 'Tape it onto the scrap',
        stamp: '⟨ taped ⟩',
        body:
            'On a finished Smelt card, tap the paste icon to tape a kraft slip onto the page. The answer and steps stay with the note. You can drag it or delete it later. Tapes are saved on the scrap even when you close it.',
      ),
      GuideTip(
        icon: Icons.swap_horiz,
        title: 'Try another model, or tap again',
        body:
            'Try another model on a Smelt card is a one-time override. Your default in Settings does not change. Tapping the same expression again reopens the last result without another request.',
      ),
    ],
  );

  static const chat = GuideSection(
    id: 'chat',
    title: 'Ask',
    subtitle: 'Follow-ups without leaving the scrap.',
    stamp: '⟨ ask ⟩',
    glyph: GuideGlyph.spark,
    tips: [
      GuideTip(
        glyph: GuideGlyph.spark,
        title: 'The button in the corner',
        body:
            'The ✦ in the bottom-right opens Ask in a split view beside the scrap. Conversations belong to the note you are in.',
      ),
      GuideTip(
        icon: Icons.crop_free,
        title: 'Attach what you selected',
        body:
            'The crop icon on the chat composer turns on lasso capture. Draw a box around the content you want to attach to the chat, so you do not have to retype what is already on the page.',
      ),
      GuideTip(
        icon: Icons.history,
        title: 'Chips and history',
        body:
            'A new thread offers chips like Explain my notes, Quiz me, and Summarize this page. History in the header (and in Settings) opens a past conversation on its scrap.',
      ),
      GuideTip(
        icon: Icons.add,
        title: 'Model chip and +',
        body:
            'The chip in the upper-left of the Ask split picks the model. That same default is used for Smelt. Tap + to start a new chat on this scrap.',
      ),
    ],
  );

  static const models = GuideSection(
    id: 'models',
    title: 'Models',
    subtitle: 'Which one to pick, and what a rate limit means.',
    stamp: '⟨ models ⟩',
    icon: Icons.settings_outlined,
    showModelChart: true,
    tips: [
      GuideTip(
        icon: Icons.settings_outlined,
        title: 'Where the default lives',
        body:
            'Settings → AI Model sets the default for Ask and Smelt. The chip in the chat header changes the same preference. Try another model on a Smelt card does not.',
      ),
      GuideTip(
        icon: Icons.schedule,
        title: 'Pick for the job, not the name',
        body:
            'Flash Lite is the default because it answers quickly and has the most room: 15 requests per minute, 500 per day. Flash is slower and stronger, but the free cap is 5 per minute and 20 per day.',
      ),
      GuideTip(
        icon: Icons.error_outline,
        title: 'When a model is rate-limited',
        body:
            'Those numbers are Google\'s free-tier limits, not Scrapyard\'s. Paid AI Studio projects can be higher. If a request hits a 429, the app tries the next model in the same family, then a lighter one. The card will say if it used a fallback.',
      ),
    ],
  );

  static const tools = GuideSection(
    id: 'tools',
    title: 'Canvas and tools',
    subtitle: 'The toolbar, plus a few things hiding in settings.',
    stamp: '⟨ tools ⟩',
    icon: Icons.edit_outlined,
    showToolStrip: true,
    tips: [
      GuideTip(
        icon: Icons.category_outlined,
        title: 'Hold still for a shape or line',
        body:
            'With Shape snapping on (it is, by default), pause about a third of a second while drawing with pen or brush. The stroke snaps to a line, circle, oval, rectangle, square, triangle, diamond, or star. A live preview shows what it will become.',
      ),
      GuideTip(
        glyph: GuideGlyph.lasso,
        title: 'Lasso, copy, paste',
        body:
            'Drag a rectangle to select. From the menu you can resize, copy, or delete. Long-press empty paper when something is on the clipboard to paste.',
      ),
      GuideTip(
        icon: Icons.circle,
        title: 'Colour wells',
        body:
            'Six wells sit on the toolbar. A custom pick overwrites that slot. With palm rejection on, a stylus tap selects the colour and a finger tap opens the picker. With it off, tap selects and a double-tap opens the picker.',
      ),
      GuideTip(
        icon: Icons.calculate_outlined,
        title: 'Quick calc',
        stamp: '⟨ Quick Calc ⟩',
        body:
            'Off by default, in canvas settings. Write a simple expression and an equals sign. An on-device AI model detects the expression and fills in the answer to the right. No API key is required. Tap the answer to send it through Smelt instead, or to remove it. \nNote: This is a beta feature and may not be consistently reliable. Supports simple arithmetic only. It is not a substitute for Smelt.',
      ),
      GuideTip(
        icon: Icons.settings_outlined,
        title: 'Page style, Infinite, Go Home',
        body:
            'Plain, Ruled, Dotted, or Grid, set per scrap. Infinite is one-way. You cannot return that note to a fixed page. Finite scraps add sheets as you write, up to forty. On Infinite, pinch to pan and zoom. Go Home jumps back to where you first wrote.',
      ),
      GuideTip(
        icon: Icons.pan_tool_alt_outlined,
        title: 'Draw vs scroll',
        body:
            'The pencil / pan toggle on the toolbar switches modes. In scroll, fingers pan and zoom and nothing inks. Leaving draw while Lasso or Smelt is active drops you back to pen, so you do not keep selecting by accident.',
      ),
    ],
  );

  static const stylus = GuideSection(
    id: 'stylus',
    title: 'Stylus and gestures',
    subtitle: 'Palm rejection, the S Pen button, undo, and redo.',
    stamp: '⟨ stylus ⟩',
    icon: Icons.back_hand_outlined,
    tips: [
      GuideTip(
        icon: Icons.back_hand_outlined,
        title: 'Palm rejection',
        body:
            'Canvas settings → Palm rejection: touch pans and zooms, stylus writes. It defaults on for tablets. The first time a stylus appears it turns on unless you already chose. Fingers can still pinch. Turn it off if you write with a finger.',
      ),
      GuideTip(
        glyph: GuideGlyph.eraser,
        title: 'S Pen button eraser',
        body:
            'Settings → Gestures → S Pen Button Eraser (on by default). Hold the side button to erase. Release and you are back on the previous tool. The same trick works on other styluses that report a secondary button.',
      ),
      GuideTip(
        glyph: GuideGlyph.eraser,
        title: 'Hover ring',
        body:
            'With the eraser selected, a stylus in proximity shows a size ring before you touch down. It fades shortly after hover ends.',
      ),
      GuideTip(
        icon: Icons.undo_outlined,
        title: 'Two-finger undo, three-finger redo',
        body:
            'A quick two-finger tap undoes. A three-finger tap redoes. These are multi-finger taps, not a double-tap with one finger. Both can be turned off under Settings → Gestures. The toolbar buttons still work. History keeps the last sixty actions.',
      ),
    ],
  );

  static const desk = GuideSection(
    id: 'desk',
    title: 'The desk',
    subtitle: 'Scraps, piles, PDFs, and recently deleted.',
    stamp: '⟨ desk ⟩',
    icon: Icons.folder_outlined,
    tips: [
      GuideTip(
        icon: Icons.add,
        title: 'New scrap and loose scrap',
        body:
            'New scrap lives on the desk card (and the + menu on a portrait strip). It stays pending until you leave or close it, then you can name it. Loose scrap never files.',
      ),
      GuideTip(
        icon: Icons.folder_outlined,
        title: 'Piles',
        body:
            'New folder makes a pile. Drag a card onto a pile to move it, or use the card menu to rename or Move to pile.',
      ),
      GuideTip(
        icon: Icons.upload_outlined,
        title: 'Import a PDF or image',
        body:
            'PDFs open in the in-app viewer with a floating annotation bar: pan, pen, highlighter, eraser, Smelt, colours. Images open in the system viewer. You can split a PDF beside a scrap of paper, and Ask still sits in the corner. Smelt on a PDF crop does not tape onto the page.',
      ),
      GuideTip(
        icon: Icons.star_outline_rounded,
        title: 'Saved, crush, thirty days',
        body:
            'Star a scrap or PDF and it also appears under Saved. It is still in its original pile. Crush sends it to Recently Deleted for thirty days. Restore from there, or crush again to delete for good.',
      ),
      GuideTip(
        icon: Icons.layers_outlined,
        title: 'Tabs',
        body:
            'Open scraps stack as filing tabs. Long-press a tab to group it with another, name a pending scrap, crush a loose one, or close the others.',
      ),
      GuideTip(
        icon: Icons.more_horiz,
        title: 'Tear out',
        body:
            'Tear out is in the card menu. It shares the scrap as a PNG. ',
      ),
    ],
  );

  static const List<GuideSection> all = [
    smelt,
    chat,
    models,
    tools,
    stylus,
    desk,
  ];

  static GuideSection? byId(String id) {
    for (final section in all) {
      if (section.id == id) return section;
    }
    return null;
  }
}

class GuideTip {
  final IconData? icon;
  final GuideGlyph? glyph;
  final String title;
  final String body;
  final String? stamp;

  const GuideTip({
    this.icon,
    this.glyph,
    required this.title,
    required this.body,
    this.stamp,
  });
}

class GuideToolItem {
  final String label;
  final String caption;
  final IconData? icon;
  final GuideGlyph? glyph;

  const GuideToolItem({
    required this.label,
    required this.caption,
    this.icon,
    this.glyph,
  });

  static const List<GuideToolItem> all = [
    GuideToolItem(
      label: 'Pen',
      caption:
          'Fine ink. Tune pen, ballpoint, pencil, or marker in the settings chit.',
      icon: Icons.edit_outlined,
    ),
    GuideToolItem(
      label: 'Brush',
      caption:
          'Calligraphy, fountain, and ink brush. Pressure where the nib allows.',
      icon: Icons.brush_outlined,
    ),
    GuideToolItem(
      label: 'Highlighter',
      caption:
          'A multiply mark. Concentration defaults to half. Yellow is the starting well.',
      glyph: GuideGlyph.highlighter,
    ),
    GuideToolItem(
      label: 'Eraser',
      caption:
          'Stroke removes a whole stroke. Area carves. Thickness dots set the size.',
      glyph: GuideGlyph.eraser,
    ),
    GuideToolItem(
      label: 'Text',
      caption:
          'Tap where you want to type. Empty boxes disappear when you deselect them.',
      icon: Icons.text_fields_outlined,
    ),
    GuideToolItem(
      label: 'Shape',
      caption:
          'Draw straight lines or shapes (Supports circles, rectangles, squares, triangles, diamonds, stars, and lines).',
      icon: Icons.category_outlined,
    ),
    GuideToolItem(
      label: 'Lasso',
      caption: 'Drag a rectangle to select, resize, copy, or delete.',
      glyph: GuideGlyph.lasso,
    ),
    GuideToolItem(
      label: 'Smelt',
      caption: 'Select writing and send it to Gemini.',
      icon: Icons.auto_awesome,
    ),
  ];
}

/// Speed ticks and free-tier rate limits for the models chart.
class GuideModelInfo {
  static int speedTicks(GeminiChatModel model) {
    return switch (model.tier) {
      GeminiModelTier.flashLite => 4,
      GeminiModelTier.flash => 2,
    };
  }

  static const maxSpeedTicks = 4;

  static String rpm(GeminiChatModel model) {
    return switch (model.tier) {
      GeminiModelTier.flashLite => '15',
      GeminiModelTier.flash => '5',
    };
  }

  static String rpd(GeminiChatModel model) {
    return switch (model.tier) {
      GeminiModelTier.flashLite => '500',
      GeminiModelTier.flash => '20',
    };
  }

  static const studioRateLimitsUrl = 'https://aistudio.google.com/rate-limit';
}
