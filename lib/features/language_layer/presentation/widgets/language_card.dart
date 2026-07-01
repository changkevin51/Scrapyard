import 'package:flutter/material.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../../ai_engine/domain/models/contextual_response.dart';

class LanguageCard extends StatelessWidget {
  final ContextualResponse response;

  const LanguageCard({
    super.key,
    required this.response,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                     response.word ?? response.definition, // Fallback
                     style: KotoTextStyles.heading.copyWith(
                       fontSize: 30, // 30sp as per spec
                       fontWeight: FontWeight.w600,
                       height: 1.2,
                     ),
                   ),
                   if (response.romaji != null) ...[
                     const SizedBox(height: 2),
                     Text(
                       response.romaji!,
                       style: KotoTextStyles.caption.copyWith(
                         fontSize: 17,
                         fontStyle: FontStyle.italic,
                         color: KotoTheme.mutedText,
                       ),
                     ),
                   ]
                ],
              ),
            ),
            if (response.jlptLevel != null)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: KotoTheme.accentSurface,
                  borderRadius: BorderRadius.circular(3), // 3px radius pill
                ),
                child: Text(
                  response.jlptLevel!,
                  style: KotoTextStyles.label.copyWith(
                    color: KotoTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        
        if (response.pitchPattern != null) ...[
          const SizedBox(height: 12),
          _buildPitchPattern(response.pitchPattern!),
        ],

        if (response.explanation.isNotEmpty || (response.meaning != null && response.meaning!.isNotEmpty)) ...[
          const SizedBox(height: 16),
          Text(
            response.meaning ?? response.explanation, // Definition fallback
            style: KotoTextStyles.body.copyWith(
              fontSize: 15,
              height: 1.5,
              color: KotoTheme.bodyText,
            ),
          ),
        ],

        if (response.languageNotes != null) ...[
          const SizedBox(height: 12),
          Text(
             response.languageNotes!,
             style: KotoTextStyles.caption.copyWith(color: KotoTheme.secondaryText),
          ),
        ],

        if (response.languageExamples.isNotEmpty) ...[
          for (var i = 0; i < response.languageExamples.length; i++) ...[
             const Padding(
               padding: EdgeInsets.symmetric(vertical: 12.0),
               child: Divider(height: 1, thickness: 1, color: KotoTheme.dividers),
             ),
             _buildExample(response.languageExamples[i]),
          ]
        ],
      ],
    );
  }

  Widget _buildPitchPattern(String pattern) {
    List<Widget> dots = [];
    for (int i = 0; i < pattern.length; i++) {
       bool isHigh = pattern[i].toUpperCase() == 'H';
       
       dots.add(
         Container(
           margin: const EdgeInsets.only(right: 8),
           width: 7,
           height: 7,
           decoration: BoxDecoration(
             shape: BoxShape.circle,
             color: isHigh ? KotoTheme.accent : Colors.transparent,
             border: isHigh ? null : Border.all(color: KotoTheme.dividers, width: 1.0),
           ),
         )
       );
    }
    
    return Row(children: dots);
  }
  
  Widget _buildExample(LanguageExample example) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          example.japanese,
          style: KotoTextStyles.body.copyWith(
             color: KotoTheme.primaryText,
             height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${example.romaji} — ${example.english}',
          style: KotoTextStyles.caption.copyWith(
             color: KotoTheme.mutedText,
             fontStyle: FontStyle.italic,
             height: 1.4,
          ),
        ),
      ],
    );
  }
}
