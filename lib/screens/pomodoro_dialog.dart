import 'dart:async';

import 'package:flutter/material.dart';

import '../services/pomodoro_clock.dart';

class PomodoroDialog extends StatefulWidget {
  const PomodoroDialog({super.key, required this.arabic});

  final bool arabic;

  @override
  State<PomodoroDialog> createState() => _PomodoroDialogState();
}

class _PomodoroDialogState extends State<PomodoroDialog> {
  bool _break = false;
  bool _running = false;
  Duration _left = PomodoroClock.focus;
  DateTime? _endsAt;
  Timer? _timer;

  String _label(String english, String arabic) =>
      widget.arabic ? arabic : english;

  void _tick() {
    final end = _endsAt;
    if (end == null) return;
    final remaining = PomodoroClock.remaining(
      session: end.difference(DateTime.now()),
      elapsed: Duration.zero,
    );
    setState(() {
      _left = remaining;
      if (remaining == Duration.zero) {
        _running = false;
        _endsAt = null;
        _timer?.cancel();
      }
    });
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      final end = _endsAt;
      if (end != null) {
        _left = PomodoroClock.remaining(
          session: end.difference(DateTime.now()),
          elapsed: Duration.zero,
        );
      }
      setState(() {
        _running = false;
        _endsAt = null;
      });
      return;
    }
    if (_left == Duration.zero) return;
    setState(() {
      _running = true;
      _endsAt = DateTime.now().add(_left);
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _reset({bool? breakMode}) {
    _timer?.cancel();
    setState(() {
      _break = breakMode ?? _break;
      _running = false;
      _endsAt = null;
      _left = _break ? PomodoroClock.shortBreak : PomodoroClock.focus;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_label('Pomodoro timer', 'مؤقت بومودورو')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(_label('Focus', 'تركيز')),
            ),
            ButtonSegment(
              value: true,
              label: Text(_label('Break', 'استراحة')),
            ),
          ],
          selected: {_break},
          onSelectionChanged: (value) => _reset(breakMode: value.first),
        ),
        const SizedBox(height: 20),
        Text(
          PomodoroClock.display(_left),
          style: Theme.of(context).textTheme.displayLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: _left == Duration.zero ? null : _toggle,
              child: Text(_running
                  ? _label('Pause', 'إيقاف مؤقت')
                  : _label('Start', 'ابدأ')),
            ),
            OutlinedButton(
              onPressed: _reset,
              child: Text(_label('Reset', 'إعادة ضبط')),
            ),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(_label('Close', 'إغلاق')),
      ),
    ],
  );
}
