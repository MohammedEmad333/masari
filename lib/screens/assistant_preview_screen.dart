import 'package:flutter/material.dart';

import '../models/deadline.dart';
import '../services/assistant_preview_service.dart';

/// Safe, offline assistant concept. A live AI proxy is not connected yet.
class AssistantPreviewScreen extends StatefulWidget {
  const AssistantPreviewScreen({
    super.key,
    required this.deadlines,
    required this.arabic,
  });

  final List<Deadline> deadlines;
  final bool arabic;

  @override
  State<AssistantPreviewScreen> createState() => _AssistantPreviewScreenState();
}

class _AssistantPreviewScreenState extends State<AssistantPreviewScreen> {
  final _input = TextEditingController();
  AssistantInterpretation? _interpretation;

  String t(String en, String ar) => widget.arabic ? ar : en;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _analyze() {
    FocusScope.of(context).unfocus();
    setState(() {
      _interpretation = AssistantPreviewService.interpret(_input.text);
    });
  }

  void _example(String text) {
    _input.text = text;
    _analyze();
  }

  @override
  Widget build(BuildContext context) {
    final result = _interpretation;
    return Scaffold(
      appBar: AppBar(title: Text(t('Assistant preview', 'معاينة المساعد'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t(
                        'Offline prototype: reads tasks already on your '
                            'device. It does not contact an AI model, share data, '
                            'change deadlines, or schedule reminders.',
                        'نموذج أولي يعمل محليًا: يقرأ المهام المحفوظة على '
                            'جهازك فقط. لا يتصل بالذكاء الاصطناعي ولا يشارك '
                            'البيانات أو يغير المواعيد أو يجدول إشعارات.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            minLines: 1,
            maxLines: 3,
            maxLength: 250,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _analyze(),
            decoration: InputDecoration(
              labelText: t('Ask about your tasks', 'اسأل عن مهامك'),
              hintText: t(
                'e.g. Show overdue tasks',
                'مثلاً: اعرض مهامي المتأخرة',
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _analyze,
            icon: const Icon(Icons.search_rounded),
            label: Text(t('Preview request', 'معاينة الطلب')),
          ),
          const SizedBox(height: 16),
          Text(
            t('Try an example', 'جرّب مثالاً'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(
                label: Text(t('Today', 'مهام اليوم')),
                onPressed: () => _example(t('Tasks today', 'مهامي اليوم')),
              ),
              ActionChip(
                label: Text(t('Overdue', 'المتأخرة')),
                onPressed: () =>
                    _example(t('Show overdue tasks', 'اعرض مهامي المتأخرة')),
              ),
              ActionChip(
                label: Text(t('Next 7 days', 'الأيام السبعة القادمة')),
                onPressed: () => _example(
                  t('Upcoming tasks this week', 'مهامي الأسبوع القادم'),
                ),
              ),
              ActionChip(
                label: Text(t('Reminder', 'تذكير')),
                onPressed: () => _example(
                  t('Remind me 10 minutes before', 'ذكرني قبل ١٠ دقائق'),
                ),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            _renderResult(result),
          ],
        ],
      ),
    );
  }

  Widget _renderResult(AssistantInterpretation result) {
    if (result.intent == AssistantIntent.reminderPreview) {
      final minutes = result.reminderMinutes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('Reminder suggestion only', 'اقتراح تذكير فقط'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            minutes == null
                ? t(
                    'Specify an interval such as "10 minutes before". '
                        'Choose the task and reminder manually.',
                    'حدّد مدة مثل «قبل ١٠ دقائق»، ثم اختر المهمة '
                        'والتذكير يدويًا.',
                  )
                : t(
                    'Suggested offset: $minutes minutes before the due '
                        'time. No notification was created. Confirm the '
                        'task and deadline manually.',
                    'المدة المقترحة: قبل الموعد بـ$minutes دقيقة. '
                        'لم يُنشأ أي إشعار. راجع المهمة والموعد يدويًا.',
                  ),
          ),
        ],
      );
    }
    if (result.intent == AssistantIntent.unsupported) {
      return Text(
        t(
          'This request is not supported in the local prototype. '
              'No task has been modified.',
          'هذا الطلب غير مدعوم في النموذج المحلي، ولم تتغير أي مهمة.',
        ),
      );
    }

    final matches = AssistantPreviewService.matchingDeadlines(
      widget.deadlines,
      result.intent,
      now: DateTime.now(),
    );
    final heading = switch (result.intent) {
      AssistantIntent.today => t('Tasks today', 'مهام اليوم'),
      AssistantIntent.overdue => t('Overdue tasks', 'المهام المتأخرة'),
      AssistantIntent.nextSevenDays => t(
        'Next 7 days',
        'المهام خلال الأيام السبعة القادمة',
      ),
      AssistantIntent.reminderPreview || AssistantIntent.unsupported => '',
    };
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$heading (${matches.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (matches.isEmpty)
          Text(t('No matching tasks.', 'لا توجد مهام مطابقة.')),
        for (final deadline in matches.take(10))
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: Text(deadline.title),
              subtitle: Text(
                [
                  if (deadline.course.isNotEmpty) deadline.course,
                  localizations.formatMediumDate(deadline.due.toLocal()),
                  localizations.formatTimeOfDay(
                    TimeOfDay.fromDateTime(deadline.due.toLocal()),
                    alwaysUse24HourFormat: true,
                  ),
                ].join(' · '),
              ),
            ),
          ),
        if (matches.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t(
                'Showing the first 10 of ${matches.length} tasks.',
                'يُعرض أول 10 مهام من أصل ${matches.length}.',
              ),
            ),
          ),
      ],
    );
  }
}
