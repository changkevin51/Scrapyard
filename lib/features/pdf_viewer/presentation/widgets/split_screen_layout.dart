import 'package:flutter/material.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';

/// Resizable PDF | scrap layout.
///
/// The [leftChild] always occupies the first [Expanded] slot so toggling
/// [split] never disposes/recreates it (critical for a shared
/// [PdfViewerController] — pdfrx detaches the controller on dispose).
class SplitScreenLayout extends StatefulWidget {
  final Widget leftChild;
  final Widget rightChild;
  final bool split;

  const SplitScreenLayout({
    super.key,
    required this.leftChild,
    required this.rightChild,
    this.split = true,
  });

  @override
  State<SplitScreenLayout> createState() => _SplitScreenLayoutState();
}

class _SplitScreenLayoutState extends State<SplitScreenLayout> {
  double _splitRatio = 0.55;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final targetRatio = widget.split ? _splitRatio : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: targetRatio),
          duration: _dragging ? Duration.zero : ScrapMotion.panel,
          curve: ScrapMotion.panelCurve,
          builder: (context, animatedRatio, _) {
            // Keep left child in a stable Expanded slot (index 0) forever.
            final leftFlex = (animatedRatio * 1000).round().clamp(1, 1000);
            final rightFlex =
                ((1.0 - animatedRatio) * 1000).round().clamp(0, 999);
            final showRight = widget.split && rightFlex > 0;

            return Row(
              children: [
                Expanded(
                  flex: leftFlex,
                  child: widget.leftChild,
                ),
                if (showRight) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) {
                      setState(() => _dragging = true);
                    },
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _splitRatio =
                            (_splitRatio + details.delta.dx / totalWidth)
                                .clamp(0.2, 0.8);
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      setState(() => _dragging = false);
                    },
                    child: Container(
                      width: 16,
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
                  Expanded(
                    flex: rightFlex,
                    child: widget.rightChild,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
