import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lez_pos/core/theme/app_theme.dart';
import 'package:lez_pos/features/financial/screens/cash_ledger_screen.dart';
import 'package:lez_pos/features/reports/core/providers/report_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture CashLedger FORENSIC runtime logs', (tester) async {
    final forensicLines = <String>[];
    final originalDebugPrint = debugPrint;
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed') || text.contains('RenderFlex')) return;
      originalOnError?.call(details);
    };

    debugPrint = (String? message, {int? wrapWidth}) {
      final line = message ?? '';
      if (line.contains('[CashLedger FORENSIC]') || line.contains('[CashLedger] matchingRows')) {
        forensicLines.add(line);
        print(line);
      }
      originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    };
    addTearDown(() {
      debugPrint = originalDebugPrint;
      FlutterError.onError = originalOnError;
    });

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    await tester.pumpWidget(
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
              body: SizedBox(
                width: 1920,
                height: 1080,
                child: CashLedgerScreen(),
              ),
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (forensicLines.any((l) => l.contains('scroll.maxScrollExtent'))) {
        await tester.pump(const Duration(milliseconds: 500));
        break;
      }
    }

    print('--- FORENSIC CAPTURE COMPLETE (${forensicLines.length} lines) ---');
    for (final line in forensicLines) {
      print(line);
    }
  });
}