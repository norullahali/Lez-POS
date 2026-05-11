import 'dart:io';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import '../../features/pos/models/invoice_models.dart';

class ThermalPrinterService {
  Future<void> printInvoice(InvoiceData data) async {
    final List<int> bytes = <int>[];

    // ── Header ─────────────────────────
    bytes.addAll(_textCenter(data.storeName ?? '', bold: true, size: 2));

    if (data.phone != null) {
      bytes.addAll(_textCenter(data.phone!));
    }

    if (data.address != null) {
      bytes.addAll(_textCenter(data.address!));
    }

    bytes.addAll(_divider());

    // ── Items ─────────────────────────
    for (final item in data.items) {
      bytes.addAll(_textLeft('${item.name}'));
      bytes.addAll(_textLeft(
          '${item.qty} x ${item.unitPrice} = ${item.lineTotal.toStringAsFixed(0)}'));
    }

    bytes.addAll(_divider());

    // ── Total ─────────────────────────
    bytes.addAll(_textRight(
      'الإجمالي: ${data.total.toStringAsFixed(0)} د.ع',
      bold: true,
      size: 2,
    ));
    if (data.paid != null) {
      bytes.addAll(_textRight('المدفوع: ${data.paid!.toStringAsFixed(0)}'));
    }

    if (data.change != null) {
      bytes.addAll(_textRight('الباقي: ${data.change!.toStringAsFixed(0)}'));
    }

    bytes.addAll(_divider());

    // ── Footer ─────────────────────────
    if (data.footer != null && data.footer!.isNotEmpty) {
      bytes.addAll(_textCenter(data.footer!));
    }

    bytes.addAll(_feed(2));
    bytes.addAll(_cut());

    await printRaw(Uint8List.fromList(bytes));
  }

  // ───────────────── Helpers ─────────────────

  List<int> _textCenter(String text, {bool bold = false, int size = 0}) {
    return [
      0x1B,
      0x61,
      0x01,
      if (bold) ...[0x1B, 0x45, 0x01],
      if (size == 2) ...[0x1D, 0x21, 0x11],
      ...text.codeUnits,
      0x0A,
      0x1B,
      0x45,
      0x00,
      0x1D,
      0x21,
      0x00,
    ];
  }

  List<int> _textLeft(String text) {
    return [0x1B, 0x61, 0x00, ...text.codeUnits, 0x0A];
  }

  List<int> _textRight(String text, {bool bold = false, int size = 0}) {
    return [
      0x1B,
      0x61,
      0x02,
      if (bold) ...[0x1B, 0x45, 0x01],
      if (size == 2) ...[0x1D, 0x21, 0x11],
      ...text.codeUnits,
      0x0A,
      0x1B,
      0x45,
      0x00,
      0x1D,
      0x21,
      0x00,
    ];
  }

  List<int> _divider() {
    return [...'------------------------------'.codeUnits, 0x0A];
  }

  List<int> _feed(int n) {
    return List.filled(n, 0x0A);
  }

  List<int> _cut() {
    return [0x1D, 0x56, 0x00];
  }

  Future<void> printRaw(Uint8List bytes) async {
    print("🚀 Start RAW printing...");
    final printerNamePtr = TEXT(''); // default printer

    final phPrinter = calloc<IntPtr>();

    final success = OpenPrinter(printerNamePtr, phPrinter, nullptr);
    print("OpenPrinter result: $success");
    if (success == 0) {
      print('❌ Failed to open printer');
      return;
    }

    final docInfo = calloc<DOC_INFO_1>()
      ..ref.pDocName = TEXT('Lez POS')
      ..ref.pDatatype = TEXT('RAW');

    StartDocPrinter(phPrinter.value, 1, docInfo.cast());
    StartPagePrinter(phPrinter.value);

    final dataPtr = calloc<Uint8>(bytes.length);
    final dataList = dataPtr.asTypedList(bytes.length);
    dataList.setAll(0, bytes);

    final written = calloc<Uint32>();

    WritePrinter(
      phPrinter.value,
      dataPtr,
      bytes.length,
      written,
    );

    EndPagePrinter(phPrinter.value);
    EndDocPrinter(phPrinter.value);
    ClosePrinter(phPrinter.value);

    calloc.free(dataPtr);
    calloc.free(written);
    calloc.free(docInfo);
    calloc.free(phPrinter);

    print("✅ Printed via Windows RAW");
  }
}
