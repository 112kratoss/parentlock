/// App Router
/// 
/// Defines all navigation routes using GoRouter
library;

import 'package:go_router/go_router.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/parent/parent_dashboard_screen.dart';
import 'screens/parent/location_screen.dart';
import 'screens/parent/schedule_screen.dart';
import 'screens/parent/reports_screen.dart';
import 'screens/child/child_link_screen.dart';
import 'screens/child/child_active_screen.dart';

/// Global router instance
final appRouter = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  routes: [
    // Splash
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),

    // Auth Routes
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/role-selection',
      builder: (context, state) => const RoleSelectionScreen(),
    ),

    // Parent Routes
    GoRoute(
      path: '/parent/dashboard',
      builder: (context, state) => const ParentDashboardScreen(),
    ),
    // Set limits route removed

    GoRoute(
      path: '/parent/location/:childId',
      builder: (context, state) {
        final childId = state.pathParameters['childId']!;
        final childName = state.uri.queryParameters['name'];
        return LocationScreen(childId: childId, childName: childName);
      },
    ),
    GoRoute(
      path: '/parent/schedule/:childId',
      builder: (context, state) {
        final childId = state.pathParameters['childId']!;
        final childName = state.uri.queryParameters['name'];
        return ScheduleScreen(childId: childId, childName: childName);
      },
    ),
    GoRoute(
      path: '/parent/reports/:childId',
      builder: (context, state) {
        final childId = state.pathParameters['childId']!;
        final childName = state.uri.queryParameters['name'];
        return ReportsScreen(childId: childId, childName: childName);
      },
    ),

    // Child Routes
    GoRoute(
      path: '/child/link',
      builder: (context, state) => const ChildLinkScreen(),
    ),
    GoRoute(
      path: '/child/active',
      builder: (context, state) => const ChildActiveScreen(),
    ),
  ],
);
