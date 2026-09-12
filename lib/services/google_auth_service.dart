import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;

class GoogleAuthService extends ChangeNotifier {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;
  static GoogleAuthService get instance => _instance;

  GoogleAuthService._internal() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      _currentUser = account;
      notifyListeners();
    });
  }

  static final List<String> _scopes = [
    cal.CalendarApi.calendarEventsScope,
    drive.DriveApi.driveFileScope,
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: _scopes,
  );

  GoogleSignIn get googleSignIn => _googleSignIn;
  GoogleSignInAccount? _currentUser;

  GoogleSignInAccount? get currentUser => _currentUser ?? _googleSignIn.currentUser;

  Future<bool> isSignedIn() async {
    final signedIn = await _googleSignIn.isSignedIn();
    if (signedIn && _currentUser == null) {
      _currentUser = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    }
    return signedIn;
  }

  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      _currentUser = account;
      notifyListeners();
      return account;
    } catch (e) {
      debugPrint('GoogleAuthService signIn error: $e');
      return null;
    }
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      _currentUser = account;
      notifyListeners();
      return account;
    } catch (e) {
      debugPrint('GoogleAuthService signInSilently error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      notifyListeners();
    } catch (e) {
      debugPrint('GoogleAuthService signOut error: $e');
    }
  }

  Future<String?> getSignedInUserEmail() async {
    final user = currentUser ?? await signInSilently();
    return user?.email;
  }

  Future<String?> getSignedInUserDisplayName() async {
    final user = currentUser ?? await signInSilently();
    return user?.displayName;
  }

  Future<String?> getSignedInUserPhotoUrl() async {
    final user = currentUser ?? await signInSilently();
    return user?.photoUrl;
  }

  Future<http.Client?> getAuthenticatedClient({bool interactive = true}) async {
    try {
      GoogleSignInAccount? user = currentUser ?? await signInSilently();
      if (user == null && interactive) {
        user = await _googleSignIn.signIn();
        _currentUser = user;
        notifyListeners();
      }
      if (user == null) return null;
      return await _googleSignIn.authenticatedClient();
    } catch (e) {
      debugPrint('GoogleAuthService getAuthenticatedClient error: $e');
      return null;
    }
  }
}
