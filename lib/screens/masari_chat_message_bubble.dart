import 'package:flutter/material.dart';

/// A restrained, selectable message bubble for the study assistant chat.
class MasariChatMessageBubble extends StatelessWidget {
  const MasariChatMessageBubble({
    super.key,
    required this.text,
    required this.fromUser,
    required this.arabic,
    this.isError = false,
  });

  final String text;
  final bool fromUser;
  final bool arabic;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : fromUser
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    final foreground = isError
        ? scheme.onErrorContainer
        : fromUser
        ? scheme.onPrimary
        : scheme.onSurface;
    final baseStyle = TextStyle(
      color: foreground,
      fontSize: 16,
      height: 1.55,
      fontWeight: FontWeight.normal,
      decoration: TextDecoration.none,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: fromUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!fromUser) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: scheme.secondaryContainer,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .82,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(fromUser ? 18 : 5),
                    bottomRight: Radius.circular(fromUser ? 5 : 18),
                  ),
                  border: !fromUser && !isError
                      ? Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .55),
                        )
                      : null,
                ),
                child: Directionality(
                  textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
                  child: SelectableText.rich(
                    TextSpan(
                      style: baseStyle,
                      children: _formatMessage(text, baseStyle),
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _formatMessage(String value, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    final pattern = RegExp(
      r'\*\*(.+?)\*\*|\*([^*\n]+)\*|^#{1,3}\s+(.+)$',
      multiLine: true,
    );
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      final heading = match.group(3);
      spans.add(
        TextSpan(
          text: heading ?? match.group(1) ?? match.group(2) ?? '',
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            fontStyle: match.group(2) != null ? FontStyle.italic : null,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }
}
