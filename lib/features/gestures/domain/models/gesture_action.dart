enum GestureAction {
  none,
  openDocumentNavigator,
  openSettingsPanel,
  focusModeEnter,
  focusModeExit,
  toggleAnnotationToolbar,
}

enum MorseSymbol { dot, dash }

class MorsePattern {
  final List<MorseSymbol> symbols;
  const MorsePattern(this.symbols);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MorsePattern || other.symbols.length != symbols.length) return false;
    for (int i = 0; i < symbols.length; i++) {
       if (symbols[i] != other.symbols[i]) return false;
    }
    return true;
  }
  
  @override
  int get hashCode => symbols.join().hashCode;
}
