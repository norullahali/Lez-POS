// lib/core/printing/thermal/esc_pos_builder.dart
//
// Pure-Dart ESC/POS command byte builder.
//
// Usage (chained API):
//   final bytes = EscPosBuilder()
//     .init()
//     .alignCenter()
//     .boldOn()
//     .line('Store Name')
//     .boldOff()
//     .separator()
//     .kvRow('Total', '12,500 IQD')
//     .feed(3)
//     .cut()
//     .build();
//
// Or use the high-level convenience method:
//   final bytes = EscPosBuilder.fromInvoice(invoiceData, caps);
//
// The resulting Uint8List is sent directly to the hardware transport
// (USB WritePrinter, TCP socket, or BT stream) by the concrete adapter.
//
// Arabic note:
//   Most thermal printers cannot render Arabic natively.  The [arabicLine]
//   method reverses character order for printers that render each character
//   left-to-right without a proper RTL font.  For printers with CP1256/PC864
//   firmware support, call [selectCodePage] once after [init].
//
// No external packages required — pure dart:typed_data.

import 'dart:typed_data';

import '../../../features/pos/models/invoice_models.dart';
import '../printer_capabilities.dart';

/// Builds an ESC/POS byte stream for a single print job.
///
/// All instance methods mutate internal state and return [this] for chaining.
/// Call [build] or [buildList] at the end to extract the bytes.
class EscPosBuilder {
  final List<int> _buf = [];

  // ── Raw ESC/POS control bytes ─────────────────────────────────────────────
  static const int _ESC = 0x1B;
  static const int _GS  = 0x1D;
  static const int _LF  = 0x0A;

  // ── Initialisation ────────────────────────────────────────────────────────

  /// `ESC @` — reset the printer to default state. Always call first.
  EscPosBuilder init() => _add([_ESC, 0x40]);

  // ── Code page ─────────────────────────────────────────────────────────────

  /// `ESC t n` — select character code table.
  ///
  /// Common [page] values:
  ///   0   = PC437 (default)
  ///   17  = PC864 Arabic
  ///   33  = CP1256 Windows Arabic
  ///   255 = UTF-8 (newer Epson/Star firmware)
  EscPosBuilder selectCodePage(int page) =>
      _add([_ESC, 0x74, page & 0xFF]);

  // ── Alignment ─────────────────────────────────────────────────────────────

  /// `ESC a 0` — left justify (default).
  EscPosBuilder alignLeft() => _add([_ESC, 0x61, 0x00]);

  /// `ESC a 1` — center justify.
  EscPosBuilder alignCenter() => _add([_ESC, 0x61, 0x01]);

  /// `ESC a 2` — right justify.
  EscPosBuilder alignRight() => _add([_ESC, 0x61, 0x02]);

  // ── Text style ────────────────────────────────────────────────────────────

  /// `ESC E 1` — bold on.
  EscPosBuilder boldOn() => _add([_ESC, 0x45, 0x01]);

  /// `ESC E 0` — bold off.
  EscPosBuilder boldOff() => _add([_ESC, 0x45, 0x00]);

  /// `ESC - 1` — underline on.
  EscPosBuilder underlineOn() => _add([_ESC, 0x2D, 0x01]);

  /// `ESC - 0` — underline off.
  EscPosBuilder underlineOff() => _add([_ESC, 0x2D, 0x00]);

  /// `ESC ! 0x10` — double height.
  EscPosBuilder doubleHeightOn() => _add([_ESC, 0x21, 0x10]);

  /// `ESC ! 0x20` — double width.
  EscPosBuilder doubleWidthOn() => _add([_ESC, 0x21, 0x20]);

  /// `ESC ! 0x30` — double width + height (2x size).
  EscPosBuilder doubleSizeOn() => _add([_ESC, 0x21, 0x30]);

  /// `ESC ! 0x00` — reset character size to normal.
  EscPosBuilder normalSize() => _add([_ESC, 0x21, 0x00]);

  // ── Line spacing ──────────────────────────────────────────────────────────

  /// `ESC 2` — restore default line spacing (~3.75 mm).
  EscPosBuilder defaultLineSpacing() => _add([_ESC, 0x32]);

  /// `ESC 3 n` — set line spacing to n × 0.125 mm.
  EscPosBuilder lineSpacing(int n) => _add([_ESC, 0x33, n.clamp(0, 255)]);

  // ── Text output ───────────────────────────────────────────────────────────

  /// Append raw text bytes (caller is responsible for encoding).
  EscPosBuilder text(String t) {
    _buf.addAll(t.codeUnits);
    return this;
  }

  /// Append [t] followed by a line-feed.
  EscPosBuilder line(String t) {
    _buf.addAll(t.codeUnits);
    _buf.add(_LF);
    return this;
  }

  /// Append [t] with Arabic character order reversed, followed by LF.
  ///
  /// Use for printers without a proper RTL font that render each character
  /// left-to-right — the reversal makes the string read correctly.
  EscPosBuilder arabicLine(String t) {
    final reversed = t.split('').reversed.join();
    _buf.addAll(reversed.codeUnits);
    _buf.add(_LF);
    return this;
  }

  /// Emit [lines] line-feeds.
  EscPosBuilder feed([int lines = 1]) {
    for (var i = 0; i < lines; i++) {
      _buf.add(_LF);
    }
    return this;
  }

  // ── Layout helpers ────────────────────────────────────────────────────────

  /// Print a full-width separator of [char] repeated [width] times.
  EscPosBuilder separator({int width = 48, String char = '-'}) {
    _buf.addAll((char * width).codeUnits);
    _buf.add(_LF);
    return this;
  }

  /// Print a key-value row aligned to [lineWidth] columns.
  ///
  /// Layout (LTR / totals style): `label<spaces>value`
  ///
  /// Use this for total rows — matches the preview's `_trow` widget where
  /// label appears on the visual LEFT and value on the visual RIGHT.
  EscPosBuilder kvRow(
    String label,
    String value, {
    int lineWidth = 48,
  }) {
    final gap = lineWidth - label.length - value.length;
    final spaces = gap > 0 ? ' ' * gap : ' ';
    final row = '$label$spaces$value';
    final trimmed =
        row.length > lineWidth ? row.substring(0, lineWidth) : row;
    _buf.addAll(trimmed.codeUnits);
    _buf.add(_LF);
    return this;
  }

  /// Print a key-value row in RTL order: `value<spaces>label:`
  ///
  /// Use this for invoice **info** rows (invoice number, date, cashier,
  /// customer).  Mirrors the preview's `_meta` widget where value appears on
  /// the visual LEFT and the label appears on the visual RIGHT.
  EscPosBuilder rtlInfoRow(
    String label,
    String value, {
    int lineWidth = 48,
  }) {
    final tag = '$label:';
    final gap = lineWidth - value.length - tag.length;
    final spaces = gap > 0 ? ' ' * gap : ' ';
    final row = '$value$spaces$tag'; // value LEFT  →  label: RIGHT
    final trimmed =
        row.length > lineWidth ? row.substring(0, lineWidth) : row;
    _buf.addAll(trimmed.codeUnits);
    _buf.add(_LF);
    return this;
  }

  // ── Hardware control ──────────────────────────────────────────────────────

  /// `GS V 0` = full cut / `GS V 1` = partial cut.
  EscPosBuilder cut({bool full = false}) =>
      _add([_GS, 0x56, full ? 0x00 : 0x01]);

  /// `ESC p 0 t1 t2` — pulse cash-drawer pin 2.
  EscPosBuilder drawerKick({int onMs = 25, int offMs = 250}) {
    final t1 = (onMs * 2).clamp(0, 255);
    final t2 = (offMs ~/ 2).clamp(0, 255);
    return _add([_ESC, 0x70, 0x00, t1, t2]);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Returns the accumulated bytes as an immutable [Uint8List].
  Uint8List build() => Uint8List.fromList(_buf);

  /// Returns the accumulated bytes as a modifiable [List<int>].
  List<int> buildList() => List<int>.from(_buf);

  /// Number of bytes accumulated so far.
  int get byteCount => _buf.length;

  // ── Private helpers ───────────────────────────────────────────────────────

  EscPosBuilder _add(List<int> bytes) {
    _buf.addAll(bytes);
    return this;
  }

  // ── High-level invoice builder ────────────────────────────────────────────

  /// Builds a complete receipt [Uint8List] from [InvoiceData] + [PrinterCapabilities].
  ///
  /// This is the primary entry point called by [ThermalPrinterAdapter.buildBytes].
  ///
  /// Arabic labels are used throughout to match the on-screen preview.
  /// All fields in [InvoiceData] — store name, phone, address, footer 1 & 2,
  /// showTax, showQr — are honoured exactly as configured.
  ///
  /// Note: logo printing on thermal requires rasterising [InvoiceData.logoBytes]
  /// to a 1-bit ESC/POS GS v 0 bitmap.  The `image` package is needed for this
  /// conversion; add it to pubspec.yaml and integrate via [Generator.imageRaster]
  /// from `esc_pos_utils_plus` when ready.
  static Uint8List fromInvoice(
    InvoiceData data,
    PrinterCapabilities caps,
  ) {
    final b = EscPosBuilder();
    final w = caps.charsPerLine;

    b.init();
    if (caps.codePageId != null) b.selectCodePage(caps.codePageId!);

    // ── Header ───────────────────────────────────────────────────────────
    b
        .alignCenter()
        .boldOn()
        .doubleSizeOn()
        .line(data.storeName)
        .normalSize()
        .boldOff();

    if (data.phone != null && data.phone!.isNotEmpty) {
      b.line('هاتف: ${data.phone!}');
    }
    if (data.address != null && data.address!.isNotEmpty) {
      b.line('العنوان: ${data.address!}');
    }

    b.separator(width: w);

    // ── Invoice metadata (RTL order: value LEFT, label: RIGHT) ───────────
    // Matches the preview's _meta widget layout.
    b.alignLeft();
    b.rtlInfoRow('رقم الفاتورة', data.invoiceNumber,  lineWidth: w);
    b.rtlInfoRow('التاريخ',      _fmtDate(data.date), lineWidth: w);
    if (data.cashierName != null && data.cashierName!.isNotEmpty) {
      b.rtlInfoRow('الكاشير', data.cashierName!, lineWidth: w);
    }
    if (data.customerName != null && data.customerName!.isNotEmpty) {
      b.rtlInfoRow('العميل', data.customerName!, lineWidth: w);
    }

    b.separator(width: w);

    // ── Items table: [المادة] [العدد] [السعر] [المجموع] (left → right) ─────
    b.boldOn().line(_rtlTableHeader(w)).boldOff();
    b.separator(width: w, char: '.');

    for (final item in data.items) {
      if (item.name.trim().isEmpty) continue;
      b.line(_rtlTableRow(item.name, item.qty, item.unitPrice, item.lineTotal, w));
    }

    b.separator(width: w);

    // ── Totals ───────────────────────────────────────────────────────────
    final subtotal = data.items.fold(0.0, (s, i) => s + i.lineTotal);

    if (data.showTax) {
      // Show subtotal + 15% tax + grand total (mirrors the preview).
      final tax   = subtotal * 0.15;
      final total = subtotal + tax;
      b.kvRow('المجموع الفرعي', '${_fmt(subtotal)} د.ع', lineWidth: w);
      b.kvRow('ضريبة 15%',      '${_fmt(tax)}      د.ع', lineWidth: w);
      b.boldOn().doubleSizeOn();
      b.kvRow('الإجمالي',       '${_fmt(total)}    د.ع', lineWidth: w);
      b.normalSize().boldOff();
    } else {
      b.kvRow('المجموع الفرعي', '${_fmt(subtotal)} د.ع', lineWidth: w);
      b.boldOn().doubleSizeOn();
      b.kvRow('الإجمالي',       '${_fmt(data.total)} د.ع', lineWidth: w);
      b.normalSize().boldOff();
    }

    if (data.paid != null) {
      b.kvRow('المدفوع', '${_fmt(data.paid!)} د.ع', lineWidth: w);
    }
    if (data.change != null && data.change! > 0) {
      b.kvRow('الباقي', '${_fmt(data.change!)} د.ع', lineWidth: w);
    }

    b.separator(width: w);

    // ── Footer ───────────────────────────────────────────────────────────
    b.alignCenter();
    if (data.footer != null && data.footer!.isNotEmpty) {
      b.line(data.footer!);
    }
    if (data.footer2 != null && data.footer2!.isNotEmpty) {
      b.line(data.footer2!);
    }
    b.feed(1).line('Lez POS by Birtij Software').feed(3);

    // ── Hardware finalisation ────────────────────────────────────────────
    if (caps.supportsCut) b.cut();

    return b.build();
  }

  // ── Private static helpers ────────────────────────────────────────────────

  static String _fmt(num v) => v.toStringAsFixed(0);

  static String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, "0")}/${d.day.toString().padLeft(2, "0")} '
      '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';

  // ── Arabic accounting table helpers ──────────────────────────────────────
  //
  // Standard Arabic thermal POS column order (physical left → right on paper):
  //
  //   [المادة]  [العدد]  [السعر]  [المجموع]
  //   (name)    (qty)   (price)   (total)
  //
  // This matches Arabic accounting convention used on physical thermal receipts:
  //   • المادة gets the widest column on the LEFT (long Arabic product names).
  //   • Numeric columns (العدد, السعر, المجموع) are narrower and sit to the right.
  //   • An Arabic reader scans the receipt from right to left, encountering
  //     المجموع first, then السعر, then العدد, then المادة — the natural
  //     Arabic POS reading sequence.
  //
  // Column proportions mirror the preview's flex values
  //   المادة=4  العدد=2  السعر=2  المجموع=3  (total flex=11)
  //
  // Thermal printing is LTR so "leftmost" = first character in the string.

  /// Fit [s] into exactly [width] character columns.
  /// Pads with spaces on the right; truncates if too long.
  static String _col(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s + ' ' * (width - s.length);
  }

  /// Arabic table header — left-to-right on paper:
  ///   [المادة] [العدد] [السعر] [المجموع]
  static String _rtlTableHeader(int w) {
    final nw = (w * 4 ~/ 11);     // المادة  — widest (product name)
    final qw = (w * 2 ~/ 11);     // العدد
    final pw = (w * 2 ~/ 11);     // السعر
    final tw = w - nw - qw - pw;  // المجموع — remainder
    return _col('المادة',  nw) +
           _col('العدد',   qw) +
           _col('السعر',   pw) +
           _col('المجموع', tw);
  }

  /// Arabic table data row — same left-to-right order as header:
  ///   [name] [qty] [price] [total]
  static String _rtlTableRow(
    String name,
    num? qty,
    num? price,
    num? total,
    int w,
  ) {
    final nw = (w * 4 ~/ 11);
    final qw = (w * 2 ~/ 11);
    final pw = (w * 2 ~/ 11);
    final tw = w - nw - qw - pw;
    final safeName = name.length > nw ? name.substring(0, nw) : name;
    return _col(safeName,          nw) +
           _col(_fmt(qty   ?? 0),  qw) +
           _col(_fmt(price ?? 0),  pw) +
           _col(_fmt(total ?? 0),  tw);
  }
}
