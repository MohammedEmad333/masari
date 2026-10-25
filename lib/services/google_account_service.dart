import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Optional authentication. Moodle calendar tokens never leave the device.
class GoogleAccountService {
  GoogleAccountService._();

  static final GoogleAccountService instance = GoogleAccountService._();

  static const _options = FirebaseOptions(
    apiKey: 'AIzaSyApSNw-a1XHNOsgZewHHYFDUadevKxEWxY',
    appId: '1:657266784006:android:9f700e4bcd8420fed31087',
    messagingSenderId: '657266784006',
    projectId: 'masari-bb658',
    storageBucket: 'masari-bb658.firebasestorage.app',
  );

  static const _webClientId =
      '657266784006-ai622s0cibo6t9kpld590pruvgccib48.apps.googleusercontent.com';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _options);
    }
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _initialized = true;
  }

  User? get currentUser =>
      _initialized ? FirebaseAuth.instance.currentUser : null;

  Future<User?> signIn() async {
    await initialize();
    final account = await GoogleSignIn.instance.authenticate();
    final tokens = account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: tokens.idToken);
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    return result.user;
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn.instance.signOut();
  }
}
