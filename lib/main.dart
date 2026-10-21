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

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw the first Flutter frame before invoking optional Android plugins.
  // A notification/WorkManager failure must not leave users on the splash
  // screen with no UI or recovery path.
  final controller = AppController(CalendarRepository());
  runApp(MoodleReminderApp(controller: controller));
  courseChannel.setMethodCallHandler((call) async {
    if (call.method == 'courseLink' && call.arguments is String) {
      showIncomingCourse(call.arguments as String, controller);
    }
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_consumePendingCourseLink(controller));
  });
  unawaited(_bootstrap(controller));
}

Future<void> _consumePendingCourseLink(AppController controller) async {
  try {
    final link = await courseChannel.invokeMethod<String>('consumeLink');
    if (link != null) showIncomingCourse(link, controller);
  } catch (error) {
    // Sharing is optional; it must not prevent the home screen from loading.
    debugPrint('Unable to read an incoming course link: $error');
  }
}

Future<void> _bootstrap(AppController controller) async {
  controller.clearStartupError();
  try {
    await initializeDateFormatting();
    await controller.initialize();
  } catch (error, stackTrace) {
    debugPrint('Masari failed to load saved data: $error\n$stackTrace');
    controller.reportStartupError();
  }

  // Run these separately from the UI and saved-data initialization. Failures
  // are diagnostic only; the app can still display its calendar and tasks.
  unawaited(_initializeOptionalServices());
}

Future<void> _initializeOptionalServices() async {
  try {
    await NotificationService.init(requestPermissions: false);
  } catch (error) {
    debugPrint('Notification initialization failed: $error');
  }
  try {
    await BackgroundSyncService.initialize();
  } catch (error) {
    debugPrint('Background synchronization setup failed: $error');
  }
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
          home: controller.startupError == null
              ? HomeShell(controller: controller)
              : _StartupFailure(controller: controller),
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

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final arabic = controller.locale.languageCode == 'ar';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  arabic
                      ? 'تعذّر تحميل بيانات مساري.'
                      : 'Masari could not load your saved data.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  arabic
                      ? 'لم يتم حذف بياناتك. حاول مرة أخرى.'
                      : 'Your data has not been deleted. Please try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => unawaited(_bootstrap(controller)),
                  child: Text(arabic ? 'إعادة المحاولة' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
