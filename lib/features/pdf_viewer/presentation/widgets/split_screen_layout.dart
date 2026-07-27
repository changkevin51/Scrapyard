import 'package:flutter/material.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';

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
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _splitRatio),
          duration: _dragging ? Duration.zero : ScrapMotion.panel,
          curve: ScrapMotion.panelCurve,
          builder: (context, animatedRatio, _) {
            final leftWidth = totalWidth * animatedRatio;
            final rightWidth = totalWidth - leftWidth;

            return Row(
              children: [
                SizedBox(
                  width: leftWidth,
                  child: widget.leftChild,
                ),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) {
                    setState(() => _dragging = true);
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _splitRatio = (_splitRatio + details.delta.dx / totalWidth)
                          .clamp(0.2, 0.8);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    setState(() => _dragging = false);
                  },
                  child: Container(
                    width: 16, // Drag sensible hit area
                    alignment: Alignment.center,
                    child: Container(
                      width: 1,
                      height: double.infinity,
                      color: ScrapTheme.dividers,
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: ScrapTheme.accent,
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
      },
    );
  }
}
