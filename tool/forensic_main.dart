import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lez_pos/core/theme/app_theme.dart';
import 'package:lez_pos/features/financial/screens/cash_ledger_screen.dart';
import 'package:lez_pos/features/reports/core/providers/report_permissions.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        canViewAnalyticsProvider.overrideWith((ref) => true),
        canViewFinancialAnalyticsProvider.overrideWith((ref) => true),
        canExportReportsProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox.expand(child: CashLedgerScreen()),
          ),
        ),
      ),
    ),
  );
}