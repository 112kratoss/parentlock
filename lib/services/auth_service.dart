/// Authentication Service
/// 
/// Handles user authentication with Supabase including:
/// - Email/Password login and registration
/// - Google OAuth Sign-In
/// - Session management
/// - Role (parent/child) assignment
library;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Google Sign-In instance with web client ID for OAuth
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '61632775478-536h573nva64bgbbegcfbhkpn169cnim.apps.googleusercontent.com',
  );

  /// Get the current user's session
  Session? get currentSession => _supabase.auth.currentSession;

  /// Get the current user
  User? get currentUser => _supabase.auth.currentUser;

  /// Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Register a new user with email and password
  /// 
  /// Returns the new user profile after registration
  Future<UserProfile?> register({
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Registration failed: No user returned');
      }

      // Create profile using database function to bypass RLS
      await _supabase.rpc('create_profile_for_user', params: {
        'user_id': response.user!.id,
        'user_role': role,
      });

      return UserProfile(
        id: response.user!.id,
        role: role,
        createdAt: DateTime.now(),
      );
    } on AuthException catch (e) {
      throw Exception('Registration failed: ${e.message}');
    } catch (e) {
      throw Exception('Profile creation failed: ${e.toString()}');
    }
  }

  /// Login with email and password
  Future<User?> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      return response.user;
    } on AuthException catch (e) {
      throw Exception('Login failed: ${e.message}');
    }
  }

  /// Sign in with Google using native Google Sign-In
  /// 
  /// Returns the user after successful sign-in, or null if cancelled
  Future<User?> signInWithGoogle() async {
    try {
      // Trigger native Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Get authentication tokens
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception('No ID token received from Google');
      }

      // Sign in to Supabase with Google token
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.user == null) {
        throw Exception('Failed to sign in with Google');
      }

      // Check if this is a new user (no profile yet)
      final existingProfile = await getCurrentProfile();
      if (existingProfile == null) {
        // Create profile with 'pending' role - will be set in role selection
        await _supabase.rpc('create_profile_for_user', params: {
          'user_id': response.user!.id,
          'user_role': 'pending',
        });
      }

      debugPrint('Google Sign-In successful for: ${response.user!.email}');
      return response.user;
    } on AuthException catch (e) {
      throw Exception('Google sign-in failed: ${e.message}');
    } catch (e) {
      throw Exception('Google sign-in failed: ${e.toString()}');
    }
  }

  /// Sign out from Google (call this along with logout)
  Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
  }

  /// Logout the current user
  Future<void> logout() async {
    await signOutGoogle();
    await _supabase.auth.signOut();
  }

  /// Get the current user's profile from the database
  Future<UserProfile?> getCurrentProfile() async {
    if (currentUser == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', currentUser!.id)
          .single();

      return UserProfile.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Update the user's FCM token
  Future<void> updateFcmToken(String token) async {
    if (currentUser == null) return;

    await _supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', currentUser!.id);
  }

  /// Link a child account to a parent
  Future<void> linkChildToParent(String parentId) async {
    if (currentUser == null) return;

    await _supabase
        .from('profiles')
        .update({'linked_to': parentId})
        .eq('id', currentUser!.id);
  }

  /// Update user's role
  Future<void> updateRole(String role) async {
    if (currentUser == null) return;

    await _supabase
        .from('profiles')
        .update({'role': role})
        .eq('id', currentUser!.id);
  }

  /// Generate a linking code for parent-child connection
  /// This creates a temporary code that child can use to link to parent
  Future<String> generateLinkingCode() async {
    if (currentUser == null) {
      throw Exception('User not logged in');
    }

    // Simple approach: use first 8 chars of parent's ID
    // In production, you'd want a more robust system
    return currentUser!.id.substring(0, 8).toUpperCase();
  }

  /// Verify and link using parent's code
  Future<bool> linkWithCode(String code) async {
    if (currentUser == null) return false;

    try {
      // Fetch all parent profiles and filter client-side
      // (Supabase doesn't support UUID::text casting in queries)
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('role', 'parent');

      if (response.isEmpty) {
        throw Exception('No parents found');
      }

      // Find parent whose ID starts with the given code
      final codePrefix = code.toLowerCase();
      final matchingParent = response.cast<Map<String, dynamic>>().firstWhere(
        (profile) => (profile['id'] as String).toLowerCase().startsWith(codePrefix),
        orElse: () => <String, dynamic>{},
      );

      if (matchingParent.isEmpty) {
        throw Exception('Invalid linking code');
      }

      final parentId = matchingParent['id'] as String;
      await linkChildToParent(parentId);
      return true;
    } catch (e) {
      throw Exception('Failed to link: ${e.toString()}');
    }
  }
}
