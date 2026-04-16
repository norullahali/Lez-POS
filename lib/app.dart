// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_shell.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';

// Screens — imported after each module is built
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/pos/screens/pos_screen.dart';
import 'features/products/screens/products_screen.dart';
import 'features/categories/screens/categories_screen.dart';
import 'features/suppliers/screens/suppliers_screen.dart';
import 'features/suppliers/screens/supplier_payments_screen.dart';
import 'features/suppliers/screens/supplier_profile_screen.dart';
import 'features/purchases/screens/purchases_list_screen.dart';
import 'features/purchases/screens/purchase_form_screen.dart';
import 'features/opening_stock/screens/opening_stock_screen.dart';
import 'features/inventory/screens/inventory_screen.dart';
import 'features/returns/screens/customer_returns_screen.dart';
import 'features/returns/screens/supplier_returns_screen.dart';
import 'features/reports/screens/reports_screen.dart';
import 'features/users/screens/users_screen.dart';
import 'features/users/screens/roles_screen.dart';
import 'features/customers/screens/customers_screen.dart';
import 'features/customers/screens/customer_profile_screen.dart';
import 'features/customers/screens/customer_payments_screen.dart';
import 'features/backup/screens/backup_screen.dart';
import 'features/backup/screens/backup_settings_screen.dart';
import 'features/pricing/screens/pricing_rules_screen.dart';
import 'features/settings/screens/loyalty_settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authAsync = ref.watch(authProvider);
  final authState = authAsync.valueOrNull;

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      // If we're still loading, don't redirect anywhere yet
      if (authAsync.isLoading) return null;

      final isAuth = authState?.isAuthenticated ?? false;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isAuth && !isLoginRoute) return '/login';
      if (isAuth && isLoginRoute) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
      builder: (context, state, child) => AppShell(
        currentRoute: state.matchedLocation,
        child: child,
      ),
      routes: [
        GoRoute(path: '/', redirect: (_, __) => '/dashboard'),
        GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/products', builder: (_, __) => const ProductsScreen()),
        GoRoute(path: '/categories', builder: (_, __) => const CategoriesScreen()),
        GoRoute(
          path: '/customers', 
          builder: (_, __) => const CustomersScreen(),
          routes: [
            GoRoute(
              path: 'profile/:id',
              builder: (_, state) => CustomerProfileScreen(
                customerId: int.parse(state.pathParameters['id']!),
              ),
            ),
            GoRoute(
              path: 'payments',
              builder: (_, __) => const CustomerPaymentsScreen(),
            ),
            GoRoute(
              path: 'payments/:id',
              builder: (_, state) => CustomerPaymentsScreen(
                initialCustomerId: int.parse(state.pathParameters['id']!),
              ),
            ),
          ]
        ),
        GoRoute(
          path: '/suppliers', 
          builder: (_, __) => const SuppliersScreen(),
          routes: [
            GoRoute(
              path: 'payments/:id',
              builder: (_, state) => SupplierPaymentsScreen(
                supplierId: int.parse(state.pathParameters['id']!),
              ),
            ),
            GoRoute(
              path: 'profile/:id',
              builder: (_, state) => SupplierProfileScreen(
                supplierId: int.parse(state.pathParameters['id']!),
              ),
            ),
          ]
        ),
        GoRoute(
          path: '/purchases',
          builder: (_, __) => const PurchasesListScreen(),
          routes: [
            GoRoute(path: 'new', builder: (_, __) => const PurchaseFormScreen()),
            GoRoute(
              path: 'edit/:id',
              builder: (_, state) => PurchaseFormScreen(editId: int.tryParse(state.pathParameters['id'] ?? '')),
            ),
          ],
        ),
        GoRoute(path: '/opening-stock', builder: (_, __) => const OpeningStockScreen()),
        GoRoute(path: '/inventory', builder: (_, __) => const InventoryScreen()),
        GoRoute(path: '/customer-returns', builder: (_, __) => const CustomerReturnsScreen()),
        GoRoute(path: '/supplier-returns', builder: (_, __) => const SupplierReturnsScreen()),
        GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
        GoRoute(path: '/users', builder: (_, __) => const UsersScreen()),
        GoRoute(path: '/roles', builder: (_, __) => const RolesScreen()),
        GoRoute(
          path: '/backup',
          builder: (_, __) => const BackupScreen(),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (_, __) => const BackupSettingsScreen(),
            ),
          ],
        ),
        GoRoute(path: '/pricing', builder: (_, __) => const PricingRulesScreen()),
        GoRoute(path: '/loyalty-settings', builder: (_, __) => const LoyaltySettingsScreen()),
      ],
    ),
    // POS screen is full screen (no shell)
    GoRoute(path: '/pos', builder: (_, __) => const PosScreen()),
  ],
);
});

class LezPosApp extends ConsumerWidget {
  const LezPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ليز POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
  }
}
