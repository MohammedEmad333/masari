import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moodle_reminder/services/moodle_api_credentials_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final saved = <String, String>{};

  setUp(() {
    saved.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String?;
          if (call.method == 'read') return saved[key];
          if (call.method == 'write') {
            saved[key!] = args['value'] as String;
          } else if (call.method == 'delete') {
            saved.remove(key);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('rejects insecure URLs and missing tokens', () async {
    final store = MoodleApiCredentialsStore(const FlutterSecureStorage());
    await expectLater(
      store.save(server: Uri.parse('http://moodle.example'), token: 'secret'),
      throwsFormatException,
    );
    await expectLater(
      store.save(server: Uri.parse('https://moodle.example'), token: ''),
      throwsFormatException,
    );
    expect(saved, isEmpty);
  });

  test('saves loads and clears credentials through secure storage', () async {
    final store = MoodleApiCredentialsStore(const FlutterSecureStorage());
    await store.save(
      server: Uri.parse('https://moodle.example/'),
      token: 'top-secret',
    );
    expect(saved.keys, contains(MoodleApiCredentialsStore.storageKey));
    final credentials = await store.load();
    expect(credentials?.server.host, 'moodle.example');
    expect(credentials?.token, 'top-secret');
    await store.clear();
    expect(await store.load(), isNull);
  });
}
