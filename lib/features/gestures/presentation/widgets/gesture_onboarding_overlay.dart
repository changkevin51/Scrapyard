import 'package:flutter/material.dart';
import '../../../../core/theme/koto_theme.dart';

class GestureOnboardingOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const GestureOnboardingOverlay({super.key, required this.onComplete});

  @override
  State<GestureOnboardingOverlay> createState() => _GestureOnboardingOverlayState();
}

class _GestureOnboardingOverlayState extends State<GestureOnboardingOverlay> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'illustration': Icons.pan_tool_alt_outlined,
      'caption': 'Swipes: migi e (navigator), hidari e (AI)',
      'desc': 'Swipe from the absolute screen edges.',
    },
    {
      'illustration': Icons.radio_button_checked,
      'caption': 'Tap-hold: hirogeru',
      'desc': 'Hold on any text to expand the AI analysis scope.',
    },
    {
      'illustration': Icons.touch_app_outlined,
      'caption': 'Multi-finger: yubi o tsukau',
      'desc': '3-finger tap for AI. 4-finger swipe for focus.',
    },
    {
      'illustration': Icons.more_horiz,
      'caption': 'Morse: ton-tsuu',
      'desc': 'Tap dot/dash down in the bottom left corner.',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1C1C1C).withValues(alpha: 0.85),
      child: SafeArea(
        child: Stack(
          children: [
            // Skip button
            Positioned(
              top: 16,
              right: 24,
              child: GestureDetector(
                onTap: widget.onComplete,
                child: Text(
                  'Hajimeru — 始める',
                  style: KotoTextStyles.caption.copyWith(
                    color: KotoTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            
            // Pager
            Positioned.fill(
               child: PageView.builder(
                 controller: _pageController,
                 onPageChanged: (idx) => setState(() => _currentPage = idx),
                 itemCount: _pages.length,
                 itemBuilder: (context, index) {
                    final item = _pages[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         Icon(
                           item['illustration'] as IconData,
                           size: 80,
                           color: Colors.white,
                         ),
                         const SizedBox(height: 32),
                         Text(
                           item['caption'] as String,
                           style: KotoTextStyles.heading.copyWith(
                             color: Colors.white,
                             fontSize: 17,
                             fontStyle: FontStyle.italic,
                           ),
                         ),
                         const SizedBox(height: 12),
                         Text(
                           item['desc'] as String,
                           style: KotoTextStyles.body.copyWith(
                             color: Colors.white70,
                             fontSize: 15,
                           ),
                         ),
                      ],
                    );
                 },
               ),
            ),

            // Dots
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index ? KotoTheme.accent : KotoTheme.dividers,
                    ),
                  )
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
