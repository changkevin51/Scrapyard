import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/memory_providers.dart';

class UsefulnessRater extends ConsumerStatefulWidget {
  final String logId;

  const UsefulnessRater({super.key, required this.logId});

  @override
  ConsumerState<UsefulnessRater> createState() => _UsefulnessRaterState();
}

class _UsefulnessRaterState extends ConsumerState<UsefulnessRater> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fade;
  bool _acted = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));
    
    _animController.forward();

    // Fade out entirely after 1.8 seconds.
    Timer(const Duration(milliseconds: 1800), () {
       if (mounted && !_acted) {
          _animController.reverse();
       }
    });
  }

  void _submit(bool useful) {
     if (_acted) return;
     setState(() => _acted = true);
     ref.read(memoryServiceProvider).recordUsefulness(widget.logId, useful);
     _animController.reverse();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_acted && _animController.isDismissed) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _fade,
      builder: (context, child) {
        return Opacity(
           opacity: _fade.value,
           child: Row(
             mainAxisSize: MainAxisSize.min,
             children: [
                GestureDetector(
                   onTap: () => _submit(true),
                   child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.transparent,
                      child: const Text('○', style: TextStyle(fontSize: 18, color: KotoTheme.mutedText)),
                   ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                   onTap: () => _submit(false),
                   child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.transparent,
                      child: const Text('×', style: TextStyle(fontSize: 18, color: KotoTheme.mutedText)),
                   ),
                ),
             ],
           ),
        );
      },
    );
  }
}
