import 'package:flutter/material.dart';

import '../theme/masari_theme.dart';

/// Question composer. Pressing Ask AI is the user's explicit send action;
/// no separate per-question checkbox interrupts the flow.
class MasariAssistantComposer extends StatelessWidget {
  const MasariAssistantComposer({
    super.key,
    required this.controller,
    required this.arabic,
    required this.loading,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool arabic;
  final bool loading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          maxLines: 5,
          minLines: 2,
          maxLength: 500,
          enabled: !loading,
          decoration: InputDecoration(
            labelText: arabic ? 'سؤالك' : 'Your question',
            hintText: arabic
                ? 'كيف أُنظّم المراجعة قبل الامتحان؟'
                : 'How can I plan revision for an exam?',
          ),
        ),
        const SizedBox(height: MasariSpacing.sm),
        FilledButton.icon(
          onPressed: loading ? null : onSend,
          icon: const Icon(Icons.send_outlined),
          label: Text(arabic ? 'اسأل المساعد' : 'Ask AI'),
        ),
        const SizedBox(height: MasariSpacing.xs),
        Text(
          arabic
              ? 'بالضغط على «اسأل المساعد»، سيتم إرسال نص سؤالك إلى خدمة الذكاء الاصطناعي الخارجية.'
              : 'Tapping “Ask AI” sends your question to the external AI service.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
