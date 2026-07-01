import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../../ai_engine/presentation/providers/contextual_engine_provider.dart';
import 'language_card.dart';

// Controls the visibility of the sidebar
final showLanguageSidebarProvider = StateProvider<bool>((ref) => false);

class LanguageSidebarPanel extends ConsumerStatefulWidget {
  const LanguageSidebarPanel({super.key});

  @override
  ConsumerState<LanguageSidebarPanel> createState() => _LanguageSidebarPanelState();
}

class _LanguageSidebarPanelState extends ConsumerState<LanguageSidebarPanel> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 300)
    );
    // Spring-like slide in from right edge
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
       parent: _controller,
       curve: Curves.easeOutBack,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _hideSidebar() async {
    await _controller.reverse();
    ref.read(showLanguageSidebarProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(contextualEngineProvider);

    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return Transform.translate(
           offset: Offset(272 * _slideAnimation.value, 0),
           child: child,
        );
      },
      child: GestureDetector(
         onHorizontalDragUpdate: (details) {
            if (details.delta.dx > 10) {
               _hideSidebar();
            }
         },
         child: Container(
             width: 272,
             decoration: const BoxDecoration(
               color: KotoTheme.cardSurface,
               border: Border(left: BorderSide(color: KotoTheme.dividers, width: 1.0)),
             ),
             child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   Padding(
                      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 16),
                      child: Text(
                         'こと語',
                         style: KotoTextStyles.caption.copyWith(
                            color: KotoTheme.accent, // Brown
                            letterSpacing: 1.2,
                         ),
                      ),
                   ),
                   const Divider(height: 1),
                   Expanded(
                     child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: _buildContent(aiState),
                     ),
                   ),
                ],
             ),
         ),
      ),
    );
  }

  Widget _buildContent(ContextualEngineState state) {
     if (state.isLoading) {
         return Center(
             child: Text('Analyzing...', style: KotoTextStyles.caption.copyWith(fontStyle: FontStyle.italic)),
         );
     }
     
     if (state.error != null) {
         return Text(state.error!, style: KotoTextStyles.caption.copyWith(color: Colors.red));
     }

     if (state.response == null) {
         return Text(
             'Select a word in your document to view language details.',
             style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText),
         );
     }

     final resp = state.response!;
     if (!resp.isLanguageContent) {
         return Text(
             'No complex language breakdown available for this word.',
             style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText),
         );
     }
     
     return LanguageCard(response: resp);
  }
}
