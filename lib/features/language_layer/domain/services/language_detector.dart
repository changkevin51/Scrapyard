import '../models/language_hint.dart';

class LanguageDetector {
  static LanguageHint detect(String text) {
    if (text.isEmpty) return LanguageHint.unknown;

    bool hasJapanese = false;
    bool hasChinese = false;
    bool hasKorean = false;
    bool hasArabic = false;
    bool hasLatin = false;

    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i);
      
      // Hiragana: U+3040–U+309F, Katakana: U+30A0–U+30FF
      if ((code >= 0x3040 && code <= 0x309F) || (code >= 0x30A0 && code <= 0x30FF)) {
        hasJapanese = true;
      }
      // Kanji: U+4E00–U+9FFF
      else if (code >= 0x4E00 && code <= 0x9FFF) {
        hasChinese = true;
      }
      // Hangul: U+AC00–U+D7AF
      else if (code >= 0xAC00 && code <= 0xD7AF) {
        hasKorean = true;
      }
      // Arabic: U+0600–U+06FF
      else if (code >= 0x0600 && code <= 0x06FF) {
        hasArabic = true;
      }
      // Latin: basic + extended
      else if ((code >= 0x0041 && code <= 0x005A) || 
               (code >= 0x0061 && code <= 0x007A) ||
               (code >= 0x00C0 && code <= 0x024F)) {
        hasLatin = true;
      }
    }

    if (hasJapanese || (hasChinese && hasJapanese)) return LanguageHint.japanese;
    if (hasChinese && !hasJapanese) return LanguageHint.chinese;
    if (hasKorean) return LanguageHint.korean;
    if (hasArabic) return LanguageHint.arabic;
    
    int scriptsCount = (hasJapanese||hasChinese ? 1 : 0) + (hasKorean ? 1 : 0) + (hasArabic ? 1 : 0) + (hasLatin ? 1 : 0);
    
    if (scriptsCount > 1) return LanguageHint.mixed;
    if (hasLatin) return LanguageHint.latin;
    
    return LanguageHint.unknown;
  }
}
