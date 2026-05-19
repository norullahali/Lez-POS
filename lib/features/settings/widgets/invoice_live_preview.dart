// lib/features/settings/widgets/invoice_live_preview.dart
//
// Live receipt preview widget rendered entirely in Flutter (no PDF).
// Receives current settings values as constructor parameters and redraws
// whenever the parent calls setState, giving real-time feedback.

import 'dart:io';

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Mock invoice data
// ---------------------------------------------------------------------------

class _MockItem {
  final String name;
  final double qty;
  final double unitPrice;
  const _MockItem(this.name, this.qty, this.unitPrice);
  double get total => qty * unitPrice;
}

const _mockItems = [
  _MockItem('شوكولاتة كتكات', 3, 1500),
  _MockItem('عصير برتقال 1L', 2, 2000),
  _MockItem('ماء معدني 500ml', 5, 500),
];

const _mockInvoiceNumber = 'POS-20260511-0042';
const _mockCustomer = 'زبون عام';
const _mockCashier = 'أحمد';
const _mockPaid = 15000.0;

// ---------------------------------------------------------------------------
// InvoiceLivePreview
// ---------------------------------------------------------------------------

/// Fully reactive thermal-receipt preview.
///
/// Every parameter maps 1-to-1 to a setting on [InvoiceSettingsScreen].
/// The parent calls setState after every field change; this widget is
/// stateless so it simply rebuilds with the new values.
class InvoiceLivePreview extends StatelessWidget {
  final String storeName;
  final String phone;
  final String address;
  final String footerText;
  final String footerText2;
  final bool showTax;
  final bool showQr;
  final String? logoPath;

  const InvoiceLivePreview({
    super.key,
    required this.storeName,
    required this.phone,
    required this.address,
    required this.footerText,
    required this.footerText2,
    required this.showTax,
    required this.showQr,
    this.logoPath,
  });

  double get _subtotal => _mockItems.fold(0.0, (s, i) => s + i.total);
  double get _tax => showTax ? _subtotal * 0.15 : 0;
  double get _total => _subtotal + _tax;
  double get _change => _mockPaid - _total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: _ReceiptPaper(
                storeName: storeName.isEmpty ? 'اسم المحل' : storeName,
                phone: phone,
                address: address,
                footerText: footerText,
                footerText2: footerText2,
                showTax: showTax,
                showQr: showQr,
                logoPath: logoPath,
                subtotal: _subtotal,
                tax: _tax,
                total: _total,
                change: _change,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panel header
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.receipt_long_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'معاينة الفاتورة',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'مباشر',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt paper card
// ---------------------------------------------------------------------------

class _ReceiptPaper extends StatelessWidget {
  final String storeName;
  final String phone;
  final String address;
  final String footerText;
  final String footerText2;
  final bool showTax;
  final bool showQr;
  final String? logoPath;
  final double subtotal;
  final double tax;
  final double total;
  final double change;

  const _ReceiptPaper({
    required this.storeName,
    required this.phone,
    required this.address,
    required this.footerText,
    required this.footerText2,
    required this.showTax,
    required this.showQr,
    required this.logoPath,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 310,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const _PerforatedEdge(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  _dash(),
                  _meta('رقم الفاتورة', _mockInvoiceNumber),
                  _meta('التاريخ', _now()),
                  _meta('الكاشير', _mockCashier),
                  _meta('العميل', _mockCustomer),
                  _dash(),
                  _buildItemsTable(),
                  _dash(),
                  _buildTotals(),
                  if (footerText.isNotEmpty || footerText2.isNotEmpty) ...[
                    _dash(),
                    _buildFooters(),
                  ],
                  if (showQr) ...[
                    _dash(),
                    _buildQr(),
                  ],
                  _dash(),
                  _branding(),
                ],
              ),
            ),
          ),
          const _PerforatedEdge(flip: true),
        ],
      ),
    );
  }

  // ---- Header --------------------------------------------------------------

  Widget _buildHeader() {
    final hasLogo = logoPath != null && logoPath!.isNotEmpty;
    final effectivePhone =
        phone.isNotEmpty ? phone : '07700000000';
    final effectiveAddress =
        address.isNotEmpty ? address : 'شارع السعدون، بغداد';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (hasLogo)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(logoPath!),
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (hasLogo) const SizedBox(height: 6),
          Text(
            storeName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'هاتف: $effectivePhone',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          Text(
            'العنوان: $effectiveAddress',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ---- Meta row ------------------------------------------------------------

  Widget _meta(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$label:',
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  // ---- Items table ---------------------------------------------------------

  Widget _buildItemsTable() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(flex: 4, child: _th('المادة', TextAlign.right)),
              Expanded(flex: 2, child: _th('الكمية', TextAlign.center)),
              Expanded(flex: 2, child: _th('السعر', TextAlign.center)),
              Expanded(flex: 3, child: _th('المجموع', TextAlign.left)),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        ..._mockItems.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.5),
            child: Row(
              children: [
                // Product name: slightly larger font (11 vs old 9)
                Expanded(
                    flex: 4,
                    child: _td(item.name, TextAlign.right, size: 11)),
                Expanded(
                    flex: 2,
                    child: _td(item.qty.toStringAsFixed(0),
                        TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: _td(_fmt(item.unitPrice), TextAlign.center)),
                Expanded(
                    flex: 3,
                    child: _td(_fmt(item.total), TextAlign.left)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Table header / cell helpers
  Widget _th(String t, TextAlign align) => Text(t,
      textAlign: align,
      style: const TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black87));

  Widget _td(String t, TextAlign align, {double size = 9}) => Text(t,
      textAlign: align,
      style: TextStyle(fontSize: size, color: Colors.black87));

  // ---- Totals --------------------------------------------------------------

  Widget _buildTotals() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          _trow('المجموع الفرعي', _fmt(subtotal)),
          if (showTax) _trow('ضريبة 15%', _fmt(tax)),
          const SizedBox(height: 3),
          // Grand total: bolder highlight box
          Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_fmt(total)} د.ع',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const Text(
                  'الإجمالي',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _trow('المدفوع', '${_fmt(_mockPaid)} د.ع'),
          _trow(
            'الباقي',
            change >= 0 ? '${_fmt(change)} د.ع' : '-- د.ع',
            valueColor: Colors.green.shade700,
          ),
        ],
      ),
    );
  }

  Widget _trow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: valueColor != null
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: valueColor ?? Colors.black87,
            ),
          ),
          Text('$label:',
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ---- Footers -------------------------------------------------------------

  Widget _buildFooters() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          if (footerText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                footerText,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade700),
              ),
            ),
          if (footerText2.isNotEmpty)
            Text(
              footerText2,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  // ---- QR placeholder (shown only when showQr == true) --------------------

  Widget _buildQr() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.grey.shade300, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: CustomPaint(painter: _QrMockPainter()),
            ),
            const SizedBox(height: 4),
            Text('QR',
                style: TextStyle(
                    fontSize: 8, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  // ---- Branding ------------------------------------------------------------

  Widget _branding() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'Lez POS by Birtij Software',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 8, color: Colors.grey.shade400),
      ),
    );
  }

  // ---- Dashed divider ------------------------------------------------------

  Widget _dash() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: List.generate(
          44,
          (i) => Expanded(
            child: Container(
              height: 1,
              color: i.isEven
                  ? Colors.grey.shade400
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  // ---- Helpers -------------------------------------------------------------

  String _fmt(double v) {
    final n = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) buf.write(',');
      buf.write(n[i]);
    }
    return buf.toString();
  }

  String _now() {
    final t = DateTime.now();
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    return '${t.year}/$m/$d $h:$mi';
  }
}

// ---------------------------------------------------------------------------
// Perforated roll edge
// ---------------------------------------------------------------------------

class _PerforatedEdge extends StatelessWidget {
  final bool flip;
  const _PerforatedEdge({this.flip = false});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleY: flip ? -1 : 1,
      child: SizedBox(
        height: 10,
        child: CustomPaint(painter: _PerforationPainter()),
      ),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;
    const r = 5.0;
    double x = r;
    while (x < size.width) {
      canvas.drawCircle(Offset(x, 0), r, paint);
      x += r * 2.5;
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => false;
}

// ---------------------------------------------------------------------------
// QR mock painter (3-corner finder + data dots)
// ---------------------------------------------------------------------------

class _QrMockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade500
      ..style = PaintingStyle.fill;

    const cs = 14.0;

    void drawCorner(double x, double y) {
      canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), paint);
      canvas.drawRect(
        Rect.fromLTWH(x + 3, y + 3, cs - 6, cs - 6),
        Paint()..color = Colors.white,
      );
    }

    drawCorner(4, 4);
    drawCorner(size.width - cs - 4, 4);
    drawCorner(4, size.height - cs - 4);

    final dots = [
      const Offset(28, 8), const Offset(34, 8), const Offset(40, 8),
      const Offset(28, 14), const Offset(40, 14),
      const Offset(28, 20), const Offset(34, 20), const Offset(40, 20),
      const Offset(8, 28), const Offset(14, 28), const Offset(20, 28),
      const Offset(28, 28), const Offset(40, 34), const Offset(46, 34),
      const Offset(8, 34), const Offset(20, 34), const Offset(28, 40),
      const Offset(34, 46), const Offset(46, 46), const Offset(52, 52),
    ];
    for (final p in dots) {
      canvas.drawRect(Rect.fromLTWH(p.dx, p.dy, 4, 4), paint);
    }
  }

  @override
  bool shouldRepaint(_QrMockPainter old) => false;
}
