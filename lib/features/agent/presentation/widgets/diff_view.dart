import 'package:flutter/material.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/agent_models.dart';

class DiffLine {
  final String text;
  final bool added;
  final bool removed;
  DiffLine(this.text, {this.added = false, this.removed = false});
}

class DiffView extends StatefulWidget {
  final RestructureResult result;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const DiffView({
    super.key,
    required this.result,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> with SingleTickerProviderStateMixin {
  late List<DiffLine> _diffs;
  bool _accepted = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _diffs = _computeSimpleDiff(widget.result.original, widget.result.proposed);
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
    _fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // Simplistic proxy word-level diff
  List<DiffLine> _computeSimpleDiff(String orig, String prop) {
     final origWords = orig.split(RegExp(r'\s+'));
     final propWords = prop.split(RegExp(r'\s+'));
     
     List<DiffLine> diffs = [];
     int o = 0, p = 0;
     while (o < origWords.length || p < propWords.length) {
         if (o < origWords.length && p < propWords.length && origWords[o] == propWords[p]) {
             diffs.add(DiffLine('${origWords[o]} '));
             o++; p++;
         } else {
             if (o < origWords.length) {
                 diffs.add(DiffLine('${origWords[o]} ', removed: true));
                 o++;
             }
             if (p < propWords.length) {
                 diffs.add(DiffLine('${propWords[p]} ', added: true));
                 p++;
             }
         }
     }
     return diffs;
  }

  void _handleAccept() {
    setState(() => _accepted = true);
    _animController.forward().then((_) {
       widget.onAccept();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted) {
      return AnimatedBuilder(
         animation: _fadeAnim,
         builder: (context, child) {
            return Container(
               color: const Color(0xFF8BAF7A).withValues(alpha: 0.15 * _fadeAnim.value),
               child: Text(widget.result.proposed, style: KotoTextStyles.body),
            );
         },
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
         color: KotoTheme.cardSurface,
         borderRadius: BorderRadius.circular(KotoTheme.borderRadiusDefault),
         border: Border.all(color: KotoTheme.dividers, width: 1.0),
         boxShadow: KotoTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Wrap(
             children: _diffs.map((d) {
                if (d.added) {
                   return Container(
                      color: const Color(0xFF8BAF7A).withValues(alpha: 0.15),
                      child: Text(d.text, style: KotoTextStyles.body.copyWith(color: const Color(0xFF4A4A4A))),
                   );
                } else if (d.removed) {
                   return Container(
                      color: const Color(0xFFC49A8A).withValues(alpha: 0.15),
                      child: Text(d.text, style: KotoTextStyles.body.copyWith(
                         decoration: TextDecoration.lineThrough,
                         color: KotoTheme.mutedText,
                      )),
                   );
                } else {
                   return Text(d.text, style: KotoTextStyles.body);
                }
             }).toList(),
           ),
           const SizedBox(height: 16),
           Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                 GestureDetector(
                    onTap: widget.onReject,
                    child: Text('Reject', style: KotoTextStyles.caption.copyWith(color: KotoTheme.accent, fontWeight: FontWeight.bold)),
                 ),
                 const SizedBox(width: 16),
                 GestureDetector(
                    onTap: _handleAccept,
                    child: Text('Accept', style: KotoTextStyles.caption.copyWith(color: KotoTheme.accent, fontWeight: FontWeight.bold)),
                 ),
              ],
           )
        ],
      )
    );
  }
}
