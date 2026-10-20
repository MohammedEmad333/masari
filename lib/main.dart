import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_controller.dart';
import 'screens/home_shell.dart';
import 'screens/local_courses_screen.dart';
import 'services/background_sync_service.dart';
import 'services/calendar_repository.dart';
import 'services/notification_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();
const courseChannel = MethodChannel('moodle_reminder/course_share');

void showIncomingCourse(String link, AppController controller) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  nav.push(
    MaterialPageRoute<void>(
      builder: (_) => LocalCoursesScreen(
        arabic: controller.locale.languageCode == 'ar',
        incomingLink: link,
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init(requestPermissions: false);
  await initializeDateFormatting();
  await BackgroundSyncService.initialize();

  final controller = AppController(CalendarRepository());
  runApp(MoodleReminderApp(controller: controller));
  courseChannel.setMethodCallHandler((call) async {
    if (call.method == 'courseLink' && call.arguments is String) {
      showIncomingCourse(call.arguments as String, controller);
    }
  });
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final link = await courseChannel.invokeMethod<String>('consumeLink');
    if (link != null) showIncomingCourse(link, controller);
  });
  unawaited(controller.initialize());
}

class MoodleReminderApp extends StatelessWidget {
  const MoodleReminderApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: controller.locale.languageCode == 'ar' ? 'مساري' : 'Masari',
          debugShowCheckedModeBanner: false,
          locale: controller.locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: controller.themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: HomeShell(controller: controller),
        );
      },
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0D63C8),
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
