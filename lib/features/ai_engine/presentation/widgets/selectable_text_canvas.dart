import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/contextual_query.dart';
import '../providers/contextual_engine_provider.dart';
import 'contextual_popup.dart';

class SelectableTextCanvas extends ConsumerStatefulWidget {
  final String text;
  final TextStyle style;

  const SelectableTextCanvas({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  ConsumerState<SelectableTextCanvas> createState() => _SelectableTextCanvasState();
}

class _SelectableTextCanvasState extends ConsumerState<SelectableTextCanvas> {
  OverlayEntry? _popupEntry;
  TextSelection _selection = const TextSelection.collapsed(offset: -1);
  final GlobalKey _textKey = GlobalKey();

  void _showPopup(BuildContext context, String selectedText, Offset position) {
    if (_popupEntry != null) {
      _popupEntry!.remove();
    }

    int contextStart = (_selection.start - 100).clamp(0, widget.text.length);
    int contextEnd = (_selection.end + 100).clamp(0, widget.text.length);
    final surroundingContext = widget.text.substring(contextStart, contextEnd);

    final query = ContextualQuery(
      selectedText: selectedText,
      surroundingContext: surroundingContext,
      queryMode: QueryMode.explain,
    );

    ref.read(contextualEngineProvider.notifier).triggerQuery(query);

    _popupEntry = OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        
        double left = position.dx;
        if (left + 340 > screenWidth) {
           left = screenWidth - 360;
           if (left < 20) left = 20;
        }
        
        double top = position.dy + 30;
        if (top + 400 > screenHeight) {
           top = position.dy - 420; // show above if near bottom
        }

        return Positioned(
          top: top,
          left: left,
          child: Material(
            color: Colors.transparent,
            child: ContextualPopup(
              onDismiss: _removePopup,
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_popupEntry!);
  }

  void _removePopup() {
    ref.read(contextualEngineProvider.notifier).clearState();
    if (_popupEntry != null) {
      _popupEntry!.remove();
      _popupEntry = null;
    }
    setState(() {
      _selection = const TextSelection.collapsed(offset: -1);
    });
  }

  TextPosition _getPosition(Offset localPosition) {
    final RenderBox? renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const TextPosition(offset: -1);
    
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: renderBox.size.width);
    return textPainter.getPositionForOffset(localPosition);
  }

  void _handleTapDown(TapDownDetails details) {
    final position = _getPosition(details.localPosition);
    final int offset = position.offset;

    if (offset < 0 || offset >= widget.text.length) {
      _removePopup();
      return;
    }

    int start = offset;
    while (start > 0 && !_isWhitespace(widget.text[start - 1])) {
      start--;
    }
    int end = offset;
    while (end < widget.text.length && !_isWhitespace(widget.text[end])) {
      end++;
    }

    if (start < end) {
      final word = widget.text.substring(start, end).trim();
      if (word.isNotEmpty) {
        setState(() {
           _selection = TextSelection(baseOffset: start, extentOffset: end);
        });
        _showPopup(context, word, details.globalPosition);
      } else {
        _removePopup();
      }
    } else {
      _removePopup();
    }
  }

  bool _isWhitespace(String char) {
    return RegExp(r'''[\s.,;!?(){}\[\]"']''').hasMatch(char);
  }
  
  int _dragStartOffset = -1;
  void _handleLongPressStart(LongPressStartDetails details) {
     final position = _getPosition(details.localPosition);
     if (position.offset < 0) return;

     _dragStartOffset = position.offset;
     setState(() {
       _selection = TextSelection(baseOffset: _dragStartOffset, extentOffset: _dragStartOffset);
     });
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
     final position = _getPosition(details.localPosition);
     if (position.offset < 0) return;

     setState(() {
       int start = _dragStartOffset;
       int end = position.offset;
       if (start > end) {
         final temp = start;
         start = end;
         end = temp;
       }
       _selection = TextSelection(baseOffset: start, extentOffset: end);
     });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
     if (!_selection.isCollapsed && _selection.start >= 0 && _selection.end <= widget.text.length) {
       final text = widget.text.substring(_selection.start, _selection.end);
       _showPopup(context, text, details.globalPosition);
     } else {
       _removePopup();
     }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: _handleLongPressEnd,
      child: Container(
        key: _textKey,
        child: Text.rich(
          TextSpan(
            children: _buildSpans(),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _buildSpans() {
     if (_selection.isCollapsed || _selection.start < 0 || _selection.end > widget.text.length) {
        return [TextSpan(text: widget.text, style: widget.style)];
     }
     
     return [
       TextSpan(text: widget.text.substring(0, _selection.start), style: widget.style),
       TextSpan(
         text: widget.text.substring(_selection.start, _selection.end),
         style: widget.style.copyWith(
           backgroundColor: KotoTheme.accentSurface,
           color: KotoTheme.accent,
         ),
       ),
       TextSpan(text: widget.text.substring(_selection.end), style: widget.style),
     ];
  }
}
