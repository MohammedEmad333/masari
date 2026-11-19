import 'package:flutter/material.dart';

import '../theme/masari_theme.dart';

/// Privacy notice for the optional study assistant.
/// Explains external processing before the user chooses to send a question.
class MasariAssistantPrivacyNotice extends StatelessWidget {
  const MasariAssistantPrivacyNotice({super.key, required this.arabic});

  final bool arabic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MasariSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.privacy_tip_outlined, color: scheme.primary),
                const SizedBox(width: MasariSpacing.sm),
                Expanded(
                  child: Text(
                    arabic ? 'خصوصية المساعد' : 'Assistant privacy',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MasariSpacing.sm),
            Text(
              arabic
                  ? 'المساعد اختياري ويحتاج إلى الإنترنت. يُرسل فقط نص السؤال الذي تكتبه إلى خادم مساري ونموذج TokenRouter الخارجي.'
                  : 'The assistant is optional and uses the internet. Only the question you type is sent to the Masari proxy and external TokenRouter model.',
            ),
            const SizedBox(height: MasariSpacing.sm),
            Text(
              arabic
                  ? 'لا تُدخل معلومات شخصية أو كلمات مرور أو رموز تقويم. لا يستطيع المساعد قراءة المهام أو جدولة التنبيهات.'
                  : 'Do not include personal information, passwords or calendar tokens. The assistant cannot read tasks or schedule reminders.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
