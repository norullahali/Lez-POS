import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/printing/print_manager.dart';
import 'package:lez_pos/core/printing/print_outcome.dart';
import 'package:lez_pos/core/printing/printer_config.dart';
import 'package:lez_pos/core/printing/printer_type_support.dart';
import 'package:lez_pos/core/services/settings_service.dart';
import 'package:lez_pos/features/pos/models/invoice_models.dart';

InvoiceData _minimalInvoice() => InvoiceData(
      invoiceNumber: 'T-1',
      storeName: 'Test Store',
      items: const [],
      total: 0,
    );

void main() {
  group('PrinterTypeSupport', () {
    test('pdf and usbThermal are supported for print delivery', () {
      expect(
        PrinterTypeSupport.isPrintDeliverySupported(PrinterType.pdf),
        isTrue,
      );
      expect(
        PrinterTypeSupport.isPrintDeliverySupported(PrinterType.usbThermal),
        isTrue,
      );
    });

    test('lan and bluetooth are not supported for print delivery', () {
      expect(
        PrinterTypeSupport.isPrintDeliverySupported(PrinterType.lanThermal),
        isFalse,
      );
      expect(
        PrinterTypeSupport.isPrintDeliverySupported(
          PrinterType.bluetoothThermal,
        ),
        isFalse,
      );
    });
  });

  group('PrintManager guard', () {
    test('lanThermal returns unsupportedConfig, not UnimplementedError', () async {
      final manager = PrintManager(
        const PrinterConfig(
          type: PrinterType.lanThermal,
          printerIp: '192.168.1.10',
        ),
      );

      final outcome = await manager.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.unsupportedConfig);
      expect(outcome.unsupportedType, PrinterType.lanThermal);
    });

    test('bluetoothThermal returns unsupportedConfig', () async {
      final manager = PrintManager(
        const PrinterConfig(
          type: PrinterType.bluetoothThermal,
          bluetoothDeviceId: 'AA:BB:CC:DD:EE:FF',
        ),
      );

      final outcome = await manager.print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.unsupportedConfig);
    });

    test('isAvailable is false for unsupported types without adapter send',
        () async {
      final manager = PrintManager(
        const PrinterConfig(type: PrinterType.lanThermal),
      );
      expect(await manager.isAvailable(), isFalse);
    });
  });

  group('Settings persistence', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.test();
    });

    tearDown(() async {
      await db.close();
    });

    test('saved lanThermal config is preserved after failed print guard',
        () async {
      final settings = SettingsService(db);
      const saved = PrinterConfig(
        type: PrinterType.lanThermal,
        printerIp: '10.0.0.50',
        printerPort: 9100,
      );
      await settings.savePrinterConfig(saved);

      final loaded = await settings.getPrinterConfig();
      expect(loaded.type, PrinterType.lanThermal);
      expect(loaded.printerIp, '10.0.0.50');

      final outcome = await PrintManager(loaded).print(_minimalInvoice());
      expect(outcome.kind, PrintOutcomeKind.unsupportedConfig);

      final afterPrint = await settings.getPrinterConfig();
      expect(afterPrint.type, PrinterType.lanThermal);
      expect(afterPrint.printerIp, '10.0.0.50');
    });

    test('usbThermal selection round-trips unchanged', () async {
      final settings = SettingsService(db);
      const saved = PrinterConfig(
        type: PrinterType.usbThermal,
        printerName: 'XP-80',
      );
      await settings.savePrinterConfig(saved);

      final loaded = await settings.getPrinterConfig();
      expect(loaded.type, PrinterType.usbThermal);
      expect(loaded.printerName, 'XP-80');
    });
  });
}
