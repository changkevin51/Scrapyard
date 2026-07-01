import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/contextual_engine_provider.dart';
import '../../../language_layer/presentation/widgets/language_card.dart';

class ContextualPopup extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const ContextualPopup({
    super.key,
    required this.onDismiss,
  });

  @override
  ConsumerState<ContextualPopup> createState() => _ContextualPopupState();
}

class _ContextualPopupState extends ConsumerState<ContextualPopup> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _translateY;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _translateY = Tween<double>(begin: 6.0, end: 0.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contextualEngineProvider);

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _translateY.value),
          child: Opacity(
            opacity: _fade.value,
            child: TapRegion(
              onTapOutside: (_) => widget.onDismiss(),
              child: _buildCard(state),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(ContextualEngineState state) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: KotoTheme.cardSurface,
        borderRadius: BorderRadius.circular(KotoTheme.borderRadiusDefault),
        border: Border.all(color: KotoTheme.dividers, width: 1.0),
        boxShadow: KotoTheme.subtleShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bookmark Stripe
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: KotoTheme.accent,
              borderRadius: BorderRadius.vertical(top: Radius.circular(KotoTheme.borderRadiusDefault)),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildContent(state),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ContextualEngineState state) {
    if (state.isLoading) {
      return Text(
        'Looking it up...',
        style: KotoTextStyles.body.copyWith(
          color: KotoTheme.mutedText,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (state.error != null) {
      return Text(
        state.error!,
        style: KotoTextStyles.body.copyWith(color: Colors.redAccent),
      );
    }

    if (state.response == null) {
      return const SizedBox();
    }

    final resp = state.response!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (resp.isLanguageContent) ...[
           LanguageCard(response: resp),
        ] else ...[
           Text(
             resp.definition,
             style: KotoTextStyles.heading.copyWith(
               fontSize: 17,
               fontWeight: FontWeight.bold,
             ),
           ),
           const SizedBox(height: 8),
           Text(
             resp.explanation,
             style: KotoTextStyles.body.copyWith(
               fontSize: 15,
               height: 1.5,
             ),
           ),
           if (resp.examples.isNotEmpty) ...[
             const Padding(
               padding: EdgeInsets.symmetric(vertical: 16.0),
               child: Divider(height: 1, thickness: 1, color: KotoTheme.dividers),
             ),
             ...resp.examples.map((e) => Padding(
                   padding: const EdgeInsets.only(bottom: 4.0),
                   child: Text(
                     e,
                     style: KotoTextStyles.caption.copyWith(
                       fontSize: 14,
                       fontStyle: FontStyle.italic,
                       color: KotoTheme.mutedText,
                     ),
                   ),
                 )),
           ],
        ],
        const SizedBox(height: 16),
        _buildActionRow(),
      ],
    );
  }

  Widget _buildActionRow() {
    return DefaultTextStyle(
      style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _ActionLink(text: 'Copy', onTap: () {}),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text('·'),
          ),
          _ActionLink(text: 'Add to notes', onTap: () {}),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text('·'),
          ),
          _ActionLink(text: 'Ask more', onTap: () {}),
        ],
      ),
    );
  }
}

class _ActionLink extends StatefulWidget {
  final String text;
  final VoidCallback onTap;

  const _ActionLink({required this.text, required this.onTap});

  @override
  State<_ActionLink> createState() => _ActionLinkState();
}

class _ActionLinkState extends State<_ActionLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          style: TextStyle(
            color: _isHovered ? KotoTheme.accent : KotoTheme.mutedText,
            fontWeight: _isHovered ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
