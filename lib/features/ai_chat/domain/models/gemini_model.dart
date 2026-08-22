/// Performance tier for tiered model fallback.
enum GeminiModelTier {
  flashLite,
  flash,
}

/// Catalog of Gemini models available for chat (and Smelt fallback).
class GeminiChatModel {
  final String id;
  final String label;
  final String blurb;
  final GeminiModelTier tier;

  /// Heavier models that may respond more slowly than Flash Lite.
  final bool mayTakeLonger;

  const GeminiChatModel({
    required this.id,
    required this.label,
    required this.blurb,
    required this.tier,
    this.mayTakeLonger = false,
  });

  static const flash35Lite = GeminiChatModel(
    id: 'gemini-3.5-flash-lite',
    label: '3.5 Flash Lite',
    blurb: 'Fastest, cheapest — default',
    tier: GeminiModelTier.flashLite,
  );

  static const flash31Lite = GeminiChatModel(
    id: 'gemini-3.1-flash-lite',
    label: '3.1 Flash Lite',
    blurb: 'Fast, lightweight',
    tier: GeminiModelTier.flashLite,
  );

  static const flash35 = GeminiChatModel(
    id: 'gemini-3.5-flash',
    label: '3.5 Flash',
    blurb: 'Stronger reasoning',
    tier: GeminiModelTier.flash,
    mayTakeLonger: true,
  );

  static const flash36 = GeminiChatModel(
    id: 'gemini-3.6-flash',
    label: '3.6 Flash',
    blurb: 'Best coding & agentic workflows',
    tier: GeminiModelTier.flash,
    mayTakeLonger: true,
  );

  /// Models shown in the picker (fast → slow).
  static const List<GeminiChatModel> all = [
    flash35Lite,
    flash31Lite,
    flash35,
    flash36,
  ];

  static const GeminiChatModel defaultModel = flash35Lite;

  static GeminiChatModel? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<GeminiChatModel> _modelsInTier(GeminiModelTier tier) {
    return all.where((m) => m.tier == tier).toList();
  }

  /// Tier-aware fallback chain for [preferredModelId].
  ///
  /// - Flash Lite → other Flash Lite
  /// - Flash → other Flash, then Flash Lites
  static List<String> fallbackChain(String preferredModelId) {
    final preferred = byId(preferredModelId);
    if (preferred == null) {
      return fallbackChain(defaultModel.id);
    }

    final chain = <String>[preferred.id];

    for (final m in _modelsInTier(preferred.tier)) {
      if (m.id != preferred.id) chain.add(m.id);
    }

    switch (preferred.tier) {
      case GeminiModelTier.flashLite:
        break;
      case GeminiModelTier.flash:
        for (final m in _modelsInTier(GeminiModelTier.flashLite)) {
          chain.add(m.id);
        }
        break;
    }

    return chain;
  }

  /// Whether an API error should trigger trying the next model in the chain.
  static bool isRetryableError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('429') ||
        msg.contains('resource_exhausted') ||
        msg.contains('rate limit') ||
        msg.contains('quota') ||
        msg.contains('unavailable') ||
        msg.contains('not found') ||
        msg.contains('404') ||
        msg.contains('503') ||
        msg.contains('500') ||
        msg.contains('overloaded');
  }

  /// Short user-facing description of why a fallback was triggered.
  static String describeFallbackReason(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('429') ||
        msg.contains('rate') ||
        msg.contains('quota') ||
        msg.contains('resource_exhausted')) {
      return 'rate limit reached';
    }
    if (msg.contains('not found') || msg.contains('404')) {
      return 'model unavailable';
    }
    if (msg.contains('unavailable') ||
        msg.contains('503') ||
        msg.contains('overloaded')) {
      return 'service temporarily unavailable';
    }
    return 'request failed';
  }

  /// User-facing note when a different model was used than requested.
  static String fallbackMessage({
    required String requestedModelId,
    required String usedModelId,
    required String reason,
  }) {
    final requested = displayLabel(requestedModelId);
    final used = displayLabel(usedModelId);
    return 'Used $used instead ($reason on $requested)';
  }

  /// Display label for a model id, or a cleaned fallback.
  static String displayLabel(String id) {
    final found = byId(id);
    if (found != null) return found.label;
    return id
        .replaceAll('gemini-', '')
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
