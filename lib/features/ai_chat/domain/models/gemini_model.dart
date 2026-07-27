/// Catalog of Gemini models available for chat (and Smelt fallback).
/// Order = default preference + fallback chain.
class GeminiChatModel {
  final String id;
  final String label;
  final String blurb;

  const GeminiChatModel({
    required this.id,
    required this.label,
    required this.blurb,
  });

  static const flash35Lite = GeminiChatModel(
    id: 'gemini-3.5-flash-lite',
    label: '3.5 Flash Lite',
    blurb: 'Fastest, cheapest — default',
  );

  static const flash31Lite = GeminiChatModel(
    id: 'gemini-3.1-flash-lite',
    label: '3.1 Flash Lite',
    blurb: 'Fallback if 3.5 Lite is unavailable',
  );

  static const flash35 = GeminiChatModel(
    id: 'gemini-3.5-flash',
    label: '3.5 Flash',
    blurb: 'Stronger reasoning',
  );

  static const flashPreview = GeminiChatModel(
    id: 'gemini-3-flash-preview',
    label: '3 Flash Preview',
    blurb: 'Preview model',
  );

  /// Default + fallback chain order.
  static const List<GeminiChatModel> all = [
    flash35Lite,
    flash31Lite,
    flash35,
    flashPreview,
  ];

  static const GeminiChatModel defaultModel = flash35Lite;

  static GeminiChatModel? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Model IDs in fallback order (for Smelt / chat services).
  static List<String> get ids => all.map((m) => m.id).toList();

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
