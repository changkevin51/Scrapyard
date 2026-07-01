import 'package:flutter/material.dart';
import '../../../../core/theme/koto_theme.dart';

class SplitScreenLayout extends StatefulWidget {
  final Widget leftChild;
  final Widget rightChild;

  const SplitScreenLayout({
    super.key,
    required this.leftChild,
    required this.rightChild,
  });

  @override
  State<SplitScreenLayout> createState() => _SplitScreenLayoutState();
}

class _SplitScreenLayoutState extends State<SplitScreenLayout> {
  double _splitRatio = 0.55;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final leftWidth = totalWidth * _splitRatio;
        final rightWidth = totalWidth - leftWidth;

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: widget.leftChild,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _splitRatio += details.delta.dx / totalWidth;
                  // Clamp to prevent either side from disappearing
                  _splitRatio = _splitRatio.clamp(0.2, 0.8);
                });
              },
              child: Container(
                width: 16, // Drag sensible hit area
                alignment: Alignment.center,
                child: Container(
                  width: 1,
                  height: double.infinity,
                  color: KotoTheme.dividers,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: KotoTheme.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: rightWidth - 16, // subtract hit area width offset
              child: widget.rightChild,
            ),
          ],
        );
      },
    );
  }
}
