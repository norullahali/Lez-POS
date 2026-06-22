// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_shell.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/unauthorized_screen.dart';
import 'features/auth/widgets/permission_route_guard.dart';
import 'core/localization/generated/app_localizations.dart';

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
import 'features/financial/screens/cash_ledger_screen.dart';
import 'features/expenses/screens/expense_screen.dart';
import 'features/users/screens/users_screen.dart';
import 'features/users/screens/roles_screen.dart';
import 'features/customers/screens/customers_screen.dart';
import 'features/customers/screens/customer_profile_screen.dart';
import 'features/customers/screens/customer_payments_screen.dart';
import 'features/backup/screens/backup_screen.dart';
//import 'features/backup/screens/backup_settings_screen.dart';
import 'features/pricing/screens/pricing_rules_screen.dart';
import 'features/settings/screens/loyalty_settings_screen.dart';
import 'features/backup/screens/settings_screen.dart';
import 'package:lez_pos/features/settings/screens/settings_home_screen.dart';
import 'package:lez_pos/features/settings/screens/invoice_settings_screen.dart';
import 'package:lez_pos/features/invoices/screens/invoice_history_screen.dart';
import 'package:lez_pos/features/returns/screens/return_analytics_dashboard_screen.dart';
import 'features/operations/screens/notification_center_screen.dart';
import 'features/automation/screens/smart_action_center_screen.dart';
import 'features/activity/screens/activity_logs_screen.dart';
import 'features/activity/screens/user_timeline_screen.dart';

Widget _guardRoute(String route, Widget child) {
  return PermissionRouteGuard.forRoute(route: route, child: child);
}

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
      GoRoute(path: '/pos', builder: (_, __) => _guardRoute('/pos', const PosScreen())),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          currentRoute: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/unauthorized',
            builder: (_, state) => UnauthorizedScreen(
              attemptedRoute: state.uri.queryParameters['from'],
              requiredPermission: state.uri.queryParameters['permission'],
            ),
          ),
          GoRoute(
            path: '/settings/invoice',
            builder: (_, __) =>
                _guardRoute('/settings/invoice', const InvoiceSettingsScreen()),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) =>
                _guardRoute('/settings', const SettingsHomeScreen()),
          ),
          GoRoute(path: '/', redirect: (_, __) => '/dashboard'),
          GoRoute(
              path: '/dashboard',
              builder: (_, __) => const DashboardScreen()),
          GoRoute(
              path: '/products',
              builder: (_, __) => _guardRoute('/products', const ProductsScreen())),
          GoRoute(
              path: '/categories',
              builder: (_, __) =>
                  _guardRoute('/categories', const CategoriesScreen())),
          GoRoute(
              path: '/customers',
              builder: (_, __) => _guardRoute('/customers', const CustomersScreen()),
              routes: [
                GoRoute(
                  path: 'profile/:id',
                  builder: (_, state) => _guardRoute(
                    '/customers',
                    CustomerProfileScreen(
                      customerId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ),
                GoRoute(
                  path: 'payments',
                  builder: (_, __) => _guardRoute(
                    '/customers',
                    const CustomerPaymentsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'payments/:id',
                  builder: (_, state) => _guardRoute(
                    '/customers',
                    CustomerPaymentsScreen(
                      initialCustomerId:
                          int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ),
              ]),
          GoRoute(
              path: '/suppliers',
              builder: (_, __) => _guardRoute('/suppliers', const SuppliersScreen()),
              routes: [
                GoRoute(
                  path: 'payments/:id',
                  builder: (_, state) => _guardRoute(
                    '/suppliers',
                    SupplierPaymentsScreen(
                      supplierId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ),
                GoRoute(
                  path: 'profile/:id',
                  builder: (_, state) => _guardRoute(
                    '/suppliers',
                    SupplierProfileScreen(
                      supplierId: int.parse(state.pathParameters['id']!),
                    ),
                  ),
                ),
              ]),
          GoRoute(
            path: '/purchases',
            builder: (_, __) =>
                _guardRoute('/purchases', const PurchasesListScreen()),
            routes: [
              GoRoute(
                  path: 'new',
                  builder: (_, __) => _guardRoute(
                        '/purchases',
                        const PurchaseFormScreen(),
                      )),
              GoRoute(
                path: 'edit/:id',
                builder: (_, state) => _guardRoute(
                  '/purchases',
                  PurchaseFormScreen(
                      editId:
                          int.tryParse(state.pathParameters['id'] ?? '')),
                ),
              ),
            ],
          ),
          GoRoute(
              path: '/opening-stock',
              builder: (_, __) =>
                  _guardRoute('/opening-stock', const OpeningStockScreen())),
          GoRoute(
              path: '/inventory',
              builder: (_, __) =>
                  _guardRoute('/inventory', const InventoryScreen())),
          GoRoute(
              path: '/customer-returns',
              builder: (_, __) => _guardRoute(
                    '/customer-returns',
                    const CustomerReturnsScreen(),
                  )),
          GoRoute(
              path: '/supplier-returns',
              builder: (_, __) => _guardRoute(
                    '/supplier-returns',
                    const SupplierReturnsScreen(),
                  )),
          GoRoute(
              path: '/reports',
              builder: (_, __) => _guardRoute('/reports', const ReportsScreen())),
          GoRoute(
              path: '/financial',
              builder: (_, __) =>
                  _guardRoute('/financial', const CashLedgerScreen())),
          GoRoute(
              path: '/financial/cash-ledger',
              redirect: (_, __) => '/financial',
          ),
          GoRoute(
              path: '/expenses',
              builder: (_, __) =>
                  _guardRoute('/expenses', const ExpenseScreen())),
          GoRoute(
            path: '/return-analytics',
            builder: (_, __) => _guardRoute(
              '/return-analytics',
              const ReturnAnalyticsDashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/operations/notifications',
            builder: (_, __) => _guardRoute(
              '/operations/notifications',
              const NotificationCenterScreen(),
            ),
          ),
          GoRoute(
            path: '/automation/actions',
            builder: (_, __) => _guardRoute(
              '/automation/actions',
              const SmartActionCenterScreen(),
            ),
          ),
          GoRoute(
            path: '/activity',
            builder: (_, __) => _guardRoute('/activity', const ActivityLogsScreen()),
            routes: [
              GoRoute(
                path: 'timeline',
                builder: (_, __) => _guardRoute('/activity/timeline', const UserTimelineScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/invoice-history',
            builder: (_, __) => _guardRoute(
              '/invoice-history',
              const InvoiceHistoryScreen(),
            ),
          ),
          GoRoute(
              path: '/users',
              builder: (_, __) => _guardRoute('/users', const UsersScreen())),
          GoRoute(
              path: '/roles',
              builder: (_, __) => _guardRoute('/roles', const RolesScreen())),
          GoRoute(
            path: '/backup',
            builder: (_, __) => _guardRoute('/backup', const BackupScreen()),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, __) => _guardRoute(
                  '/backup',
                  const SettingsScreen(),
                ),
              ),
            ],
          ),
          GoRoute(
              path: '/pricing',
              builder: (_, __) =>
                  _guardRoute('/pricing', const PricingRulesScreen())),
          GoRoute(
              path: '/loyalty-settings',
              builder: (_, __) => _guardRoute(
                    '/loyalty-settings',
                    const LoyaltySettingsScreen(),
                  )),
        ],
      ),
    ],
  );
});

class LezPosApp extends ConsumerWidget {
  const LezPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Lez POS',
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
