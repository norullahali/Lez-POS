# Review: Printing Architecture v2

**Date:** 2026-05-11
No stock logic, invoice business logic, or UI screens were modified.

---

## Architecture Diagram

  printSale() in receipt_service.dart
        |
        | loads store settings + builds InvoiceData
        |
        v
  PrintManager(config)
        |
        | routes on config.type
        |
        |-- PrinterType.pdf  ---------> PdfPrinterAdapter
        |                                 InvoicePdfBuilderClean (PDF layout)
        |                                 package:printing (OS print dialog)
        |
        |-- PrinterType.usbThermal  --> UsbThermalPrinterAdapter  [PLACEHOLDER]
        |                                 TODO: EscPosBuilder + win32 WritePrinter
        |                                 Reference: thermal_printer_service.dart
        |
        |-- PrinterType.lanThermal  --> LanThermalPrinterAdapter   [PLACEHOLDER]
        |                                 TODO: EscPosBuilder + dart:io Socket
        |
        `-- PrinterType.bluetoothThermal -> BluetoothThermalPrinterAdapter [PLACEHOLDER]
                                           TODO: EscPosBuilder + BT plugin

---

## New Files Created

lib/core/printing/
  printer_config.dart
    - PrinterType enum (pdf, usbThermal, lanThermal, bluetoothThermal)
    - PrinterSettingsKeys constants (printer_type, printer_name, printer_ip,
      printer_port, bluetooth_device_id, receipt_paper_size)
    - PrinterConfig immutable value object
    - parsePaperSize() / paperSizeToString() helpers

  printer_adapter.dart
    - abstract PrinterAdapter (print(), isAvailable())

  print_manager.dart
    - PrintManager(config) — routes to the correct adapter via switch expression

lib/core/printing/adapters/
  pdf_printer_adapter.dart
    - Uses InvoicePdfBuilderClean to render
    - Uses Printing.layoutPdf() from package:printing for OS print dialog
    - isAvailable() always returns true (OS manages availability)

  usb_thermal_printer_adapter.dart    [PLACEHOLDER]
    - Throws UnimplementedError
    - Contains detailed TODO with implementation plan and reference to
      thermal_printer_service.dart skeleton

  lan_thermal_printer_adapter.dart    [PLACEHOLDER]
    - Throws UnimplementedError
    - Contains TODO: Socket.connect + EscPosBuilder + flush/close

  bluetooth_thermal_printer_adapter.dart  [PLACEHOLDER]
    - Throws UnimplementedError
    - Contains TODO with platform-specific notes (Windows/Android/iOS)

---

## Modified Files

lib/core/services/receipt_service.dart
  BEFORE:
    - Top-level function with mixed responsibilities
    - Direct Process.run(powershell) hack for PDF printing
    - Direct ThermalPrinterService instantiation
    - Bare print() debug calls

  AFTER:
    - Top-level function printSale() collecting data and delegating
    - No printing logic — hands InvoiceData to PrintManager
    - Uses debugPrint() instead of print()
    - Imports: printing/ and settings_service only

lib/core/services/settings_service.dart
  BEFORE:
    - No printer config support
    - printer_type stored only in SharedPreferences
    - invoice_footer and show_tax stored only in SharedPreferences
    - Duplicate top-level functions setPrinterType/getPrinterType at bottom

  AFTER (additions only, existing methods untouched):
    - getPrinterConfig() — loads full PrinterConfig from app_settings DB,
      falls back to SharedPreferences for backward compatibility
    - savePrinterConfig(config) — persists all printer fields to app_settings
    - getInvoiceFooter() / setInvoiceFooter() — migrated to DB
    - getShowTax() / setShowTax() — migrated to DB
    - invoiceFooter and showTax keys added to SettingsKeys
    - Legacy top-level duplicate functions removed (replaced by comment)

lib/core/utils/invoice_pdf_builder_clean.dart
  BEFORE bugs fixed:
    1. Duplicate ReceiptPaperSize enum defined inline
       (conflict with receipt_paper_size.dart)
    2. _buildQr() and _buildFooter() were top-level functions, not methods
    3. Dead _buildTotals() method that referenced _buildHeader + _buildTable
       internally (would cause infinite-recursion if ever called)
    4. Paid/change displayed TWICE: once inline in buildInvoice() body AND
       again inside _buildPayment() — resulting in duplicate rows in PDF
    5. Import of package:pdf/pdf.dart was unused
    6. pageFormat built with manual if/switch instead of .toPageFormat() extension
    7. _formatDate had no zero-padding for month/day

  AFTER:
    - Imports ReceiptPaperSize from receipt_paper_size.dart only (re-exports it)
    - _buildQr and footer text moved inside the class as private methods
    - Dead _buildTotals removed
    - New _buildTotalSection(data, font): shows grand total, paid, change ONCE
    - New _buildFooterSection(data, font): shows custom footer text + QR + branding
    - Uses paperSize.toPageFormat() from ReceiptPaperSizeX extension
    - _formatDate now pads month/day to 2 digits
    - No more unused imports

lib/features/settings/providers/settings_provider.dart
  Added:
    - printerConfigProvider — FutureProvider<PrinterConfig>
      Loads from SettingsService.getPrinterConfig().
      Consumers fall back to PrinterConfig.defaults on loading/error.
      Invalidate after savePrinterConfig() to reload everywhere.

---

## Adapter Responsibilities

  PdfPrinterAdapter (active)
    Responsibility: build a PDF byte buffer and hand it to the OS print dialog.
    Dependencies: InvoicePdfBuilderClean, package:printing
    State: fully implemented and tested on Windows.

  UsbThermalPrinterAdapter (placeholder)
    Responsibility: send ESC/POS bytes to a USB-connected thermal printer.
    Dependencies (future): EscPosBuilder, win32 + ffi
    Activation path: set printer_type = 'usbThermal' in settings.

  LanThermalPrinterAdapter (placeholder)
    Responsibility: send ESC/POS bytes over TCP to a network thermal printer.
    Dependencies (future): EscPosBuilder, dart:io Socket
    Activation path: set printer_type = 'lanThermal', printer_ip, printer_port.

  BluetoothThermalPrinterAdapter (placeholder)
    Responsibility: send ESC/POS bytes over Bluetooth RFCOMM.
    Dependencies (future): EscPosBuilder, platform BT plugin
    Activation path: set printer_type = 'bluetoothThermal', bluetooth_device_id.

---

## Future Thermal Expansion Plan

Step 1 — EscPosBuilder utility class (lib/core/printing/esc_pos_builder.dart)
  Build a reusable byte builder that emits ESC/POS control sequences:
    - Text alignment (left/center/right)
    - Bold, double-height, double-width
    - Arabic text via CP1256 byte mapping
    - Table column layout
    - Divider lines
    - Paper feed and cut commands

Step 2 — UsbThermalPrinterAdapter (Windows)
  Wire EscPosBuilder output into the existing thermal_printer_service.dart
  printRaw() method (already working FFI skeleton).
  Move printRaw() into a win32_raw_port.dart helper.

Step 3 — LanThermalPrinterAdapter
  dart:io Socket.connect(ip, port), write bytes, close.
  Add printer availability check (Socket with 2-second timeout).

Step 4 — BluetoothThermalPrinterAdapter
  Windows: Winsock RFCOMM via ffi or win32 Bluetooth APIs.
  Mobile: consider blue_thermal_printer or flutter_bluetooth_serial plugins.

Step 5 — Printer settings screen
  Route: /settings/printer
  Fields: printer type selector, printer name / IP / port / BT device ID,
          paper size selector, test print button.
  Provider: printerConfigProvider (invalidate on save).

---

## Files Intentionally Not Modified

lib/core/services/thermal_printer_service.dart
  Kept as reference skeleton for the future UsbThermalPrinterAdapter.
  Contains working win32 OpenPrinter / WritePrinter FFI code.

lib/core/utils/invoice_generator.dart
  Orphaned helper (not imported anywhere). Kept as-is.
  Can be removed or reused when ESC/POS builder is implemented.

lib/core/widgets/invoice_preview_widget.dart
  Flutter widget for on-screen invoice preview. Kept as-is.

lib/core/utils/receipt_paper_size.dart
  Now the ONLY canonical definition of ReceiptPaperSize enum + toPageFormat().
  Not modified.

lib/features/pos/screens/pos_screen.dart
  Call site printSale(...) is unchanged — it still calls the top-level
  function in receipt_service.dart with the same signature.

---

## Legacy Code Removed

  receipt_service.dart:
    - Process.run(powershell, [...]) PDF printing hack
    - Direct ThermalPrinterService instantiation
    - Bare print() debug calls
    - Unused import: package:printing/printing.dart (now used in adapter)

  invoice_pdf_builder_clean.dart:
    - Duplicate ReceiptPaperSize enum declaration
    - _buildTotals() dead method with infinite-recursion risk
    - Top-level _buildQr() and _buildFooter() functions
    - Duplicate paid/change rows in buildInvoice() body

  settings_service.dart:
    - Duplicate top-level setPrinterType() / getPrinterType() functions
    - SharedPreferences-only storage for invoice_footer and show_tax
