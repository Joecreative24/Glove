// auth_service.dart
// Thin, focused wrapper around FirebaseAuth + Google Sign-In.
//
// This class ONLY handles credentials (the "who are you" part). Creating the
// Firestore profile, reserving the username, etc. live in higher-level
// services and are orchestrated by `GloveBackend`.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  // ── State ──────────────────────────────────────────────────────────────

  /// Emits the signed-in user (or null) whenever auth state changes.
  /// The app's router listens to this to redirect between auth/main shells.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isSignedIn => _auth.currentUser != null;

  // ── Email / password ─────────────────────────────────────────────────────

  /// Creates a brand-new email/password credential and returns it.
  /// Throws [FirebaseAuthException] on weak password, email-in-use, etc.
  Future<UserCredential> createWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Signs an existing user in with email/password.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sets the display name on the FirebaseAuth user (mirrors fullName).
  Future<void> updateDisplayName(String fullName) async {
    await _auth.currentUser?.updateDisplayName(fullName);
  }

  // ── Google ────────────────────────────────────────────────────────────────

  /// Runs the Google account picker and signs into Firebase with the result.
  /// Returns null if the user dismisses the picker. (google_sign_in v6 API.)
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  // ── Password reset ──────────────────────────────────────────────────────

  /// Sends a "reset your password" email. Powers the Forgot-Password screen.
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Turns FirebaseAuth error codes into friendly, display-ready text.
  static String describeAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'That email is already registered.';
        case 'invalid-email':
          return 'That email address looks invalid.';
        case 'weak-password':
          return 'Please choose a stronger password (6+ characters).';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'network-request-failed':
          return 'Network error. Check your connection and retry.';
        default:
          return error.message ?? 'Authentication failed.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
