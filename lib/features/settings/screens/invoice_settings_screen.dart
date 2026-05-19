import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import '../../../core/printing/print_manager.dart';
import '../../../core/printing/printer_config.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/receipt_paper_size.dart';
import '../../../features/pos/models/invoice_models.dart';
import '../widgets/invoice_live_preview.dart';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  // -- Invoice fields ---------------------------------------------------------
  final _storeNameCtrl = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _addressCtrl   = TextEditingController();
  final _footerCtrl    = TextEditingController();
  final _footer2Ctrl   = TextEditingController();

  bool    showTax  = true;
  bool    showQr   = false;
  String? logoPath;

  // -- Printer fields ---------------------------------------------------------
  PrinterType      _printerType = PrinterType.pdf;
  ReceiptPaperSize _paperSize   = ReceiptPaperSize.thermal80;

  final _printerNameCtrl = TextEditingController();
  final _printerIpCtrl   = TextEditingController();
  final _printerPortCtrl = TextEditingController(text: '9100');
  final _btDeviceIdCtrl  = TextEditingController();

  bool _isTesting = false;

  // -- Lifecycle --------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadSettings();
    for (final c in [
      _storeNameCtrl,
      _phoneCtrl,
      _addressCtrl,
      _footerCtrl,
      _footer2Ctrl,
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _storeNameCtrl,
      _phoneCtrl,
      _addressCtrl,
      _footerCtrl,
      _footer2Ctrl,
      _printerNameCtrl,
      _printerIpCtrl,
      _printerPortCtrl,
      _btDeviceIdCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  // -- Persistence ------------------------------------------------------------

  Future<void> _loadSettings() async {
    final svc = SettingsService(AppDatabase.instance);

    // -- Load from DB (primary source) -------------------------------------
    final dbPhone = await svc.getPhone();

    if (dbPhone == null) {
      // DB is empty → first launch after update.  Migrate from SharedPreferences
      // (legacy storage used by older app versions) into the DB so that the
      // print paths (which read DB) and the preview stay in sync from now on.
      final prefs = await SharedPreferences.getInstance();
      final legacyName    = prefs.getString('store_name')      ?? '';
      final legacyPhone   = prefs.getString('store_phone')     ?? '';
      final legacyAddress = prefs.getString('store_address')   ?? '';
      final legacyLogo    = prefs.getString('store_logo');
      final legacyFooter  = prefs.getString('invoice_footer')  ?? '';
      final legacyFooter2 = prefs.getString('invoice_footer2') ?? '';
      final legacyTax     = prefs.getBool('show_tax')          ?? true;
      final legacyQr      = prefs.getBool('show_qr')           ?? false;

      // Persist legacy values into DB so future reads are consistent.
      if (legacyName.isNotEmpty)    await svc.setStoreName(legacyName);
      if (legacyPhone.isNotEmpty)   await svc.setPhone(legacyPhone);
      if (legacyAddress.isNotEmpty) await svc.setAddress(legacyAddress);
      if (legacyLogo != null)       await svc.setStoreLogoPath(legacyLogo);
      if (legacyFooter.isNotEmpty)  await svc.setInvoiceFooter(legacyFooter);
      if (legacyFooter2.isNotEmpty) await svc.setInvoiceFooter2(legacyFooter2);
      await svc.setShowTax(legacyTax);
      await svc.setShowQr(legacyQr);
    }

    // -- Read final values from DB ------------------------------------------
    logoPath              = await svc.getStoreLogoPath();
    _storeNameCtrl.text   = await svc.getStoreName();
    _phoneCtrl.text       = await svc.getPhone()            ?? '';
    _addressCtrl.text     = await svc.getAddress()          ?? '';
    _footerCtrl.text      = await svc.getInvoiceFooter()    ?? '';
    _footer2Ctrl.text     = await svc.getInvoiceFooter2()   ?? '';
    showTax               = await svc.getShowTax();
    showQr                = await svc.getShowQr();

    // -- Printer config (always DB-backed) ----------------------------------
    final config = await svc.getPrinterConfig();
    _printerType          = config.type;
    _paperSize            = config.paperSize;
    _printerNameCtrl.text = config.printerName      ?? '';
    _printerIpCtrl.text   = config.printerIp        ?? '';
    _printerPortCtrl.text = config.printerPort.toString();
    _btDeviceIdCtrl.text  = config.bluetoothDeviceId ?? '';

    setState(() {});
  }

  Future<void> _saveSettings() async {
    final svc = SettingsService(AppDatabase.instance);

    // -- Invoice settings → DB (single source of truth for printing) --------
    await svc.setStoreName(_storeNameCtrl.text.trim());
    await svc.setPhone(_phoneCtrl.text.trim().isEmpty        ? null : _phoneCtrl.text.trim());
    await svc.setAddress(_addressCtrl.text.trim().isEmpty    ? null : _addressCtrl.text.trim());
    await svc.setStoreLogoPath(logoPath);
    await svc.setInvoiceFooter(_footerCtrl.text.trim().isEmpty  ? null : _footerCtrl.text.trim());
    await svc.setInvoiceFooter2(_footer2Ctrl.text.trim().isEmpty ? null : _footer2Ctrl.text.trim());
    await svc.setShowTax(showTax);
    await svc.setShowQr(showQr);

    // -- Printer config → DB ------------------------------------------------
    await svc.savePrinterConfig(PrinterConfig(
      type:              _printerType,
      paperSize:         _paperSize,
      printerName:       _printerNameCtrl.text.trim().isEmpty ? null : _printerNameCtrl.text.trim(),
      printerIp:         _printerIpCtrl.text.trim().isEmpty   ? null : _printerIpCtrl.text.trim(),
      printerPort:       int.tryParse(_printerPortCtrl.text.trim()) ?? 9100,
      bluetoothDeviceId: _btDeviceIdCtrl.text.trim().isEmpty  ? null : _btDeviceIdCtrl.text.trim(),
    ));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الحفظ بنجاح')),
    );
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => logoPath = result.files.single.path!);
    }
  }

  // -- Test print -------------------------------------------------------------

  Future<void> _testPrint() async {
    setState(() => _isTesting = true);
    try {
      // Load logo bytes so the test print matches the live preview exactly.
      Uint8List? logoBytes;
      if (logoPath != null) {
        final file = File(logoPath!);
        if (await file.exists()) logoBytes = await file.readAsBytes();
      }

      final invoice = InvoiceData(
        invoiceNumber: 'TEST-001',
        storeName:     _storeNameCtrl.text.isEmpty ? 'Lez POS' : _storeNameCtrl.text,
        phone:         _phoneCtrl.text.isEmpty    ? null : _phoneCtrl.text,
        address:       _addressCtrl.text.isEmpty  ? null : _addressCtrl.text,
        logoBytes:     logoBytes,
        footer:        _footerCtrl.text.isEmpty   ? null : _footerCtrl.text,
        footer2:       _footer2Ctrl.text.isEmpty  ? null : _footer2Ctrl.text,
        showTax:       showTax,
        showQr:        showQr,
        total:         15000,
        paid:          20000,
        change:        5000,
        date:          DateTime.now(),
        items: [
          InvoiceItem(name: 'بضاعة تجريبية ١', qty: 2, unitPrice: 5000, lineTotal: 10000),
          InvoiceItem(name: 'بضاعة تجريبية ٢', qty: 1, unitPrice: 5000, lineTotal: 5000),
        ],
      );

      final config = PrinterConfig(
        type:             _printerType,
        paperSize:        _paperSize,
        printerName:      _printerNameCtrl.text.trim().isEmpty ? null : _printerNameCtrl.text.trim(),
        printerIp:        _printerIpCtrl.text.trim().isEmpty   ? null : _printerIpCtrl.text.trim(),
        printerPort:      int.tryParse(_printerPortCtrl.text.trim()) ?? 9100,
        bluetoothDeviceId: _btDeviceIdCtrl.text.trim().isEmpty ? null : _btDeviceIdCtrl.text.trim(),
      );

      await PrintManager(config).print(invoice);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت الطباعة التجريبية بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشلت الطباعة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: settings form
          SizedBox(
            width: 420,
            child: _SettingsForm(
              // Invoice
              storeNameCtrl:    _storeNameCtrl,
              phoneCtrl:        _phoneCtrl,
              addressCtrl:      _addressCtrl,
              footerCtrl:       _footerCtrl,
              footer2Ctrl:      _footer2Ctrl,
              showTax:          showTax,
              showQr:           showQr,
              logoPath:         logoPath,
              onShowTaxChanged: (v) => setState(() => showTax = v),
              onShowQrChanged:  (v) => setState(() => showQr  = v),
              onPickLogo:       _pickLogo,
              onSave:           _saveSettings,
              // Printer
              printerType:           _printerType,
              paperSize:             _paperSize,
              printerNameCtrl:       _printerNameCtrl,
              printerIpCtrl:         _printerIpCtrl,
              printerPortCtrl:       _printerPortCtrl,
              btDeviceIdCtrl:        _btDeviceIdCtrl,
              onPrinterTypeChanged:  (v) => setState(() => _printerType = v),
              onPaperSizeChanged:    (v) => setState(() => _paperSize   = v),
              isTesting:             _isTesting,
              onTestPrint:           _testPrint,
            ),
          ),

          const SizedBox(width: 28),

          // Right column: live preview — updates in real time as fields change.
          Expanded(
            child: InvoiceLivePreview(
              storeName:   _storeNameCtrl.text,
              phone:       _phoneCtrl.text,
              address:     _addressCtrl.text,
              footerText:  _footerCtrl.text,
              footerText2: _footer2Ctrl.text,
              showTax:     showTax,
              showQr:      showQr,
              logoPath:    logoPath,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Settings form
// -----------------------------------------------------------------------------

class _SettingsForm extends StatelessWidget {
  // Invoice params
  final TextEditingController storeNameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController footerCtrl;
  final TextEditingController footer2Ctrl;
  final bool                  showTax;
  final bool                  showQr;
  final String?               logoPath;
  final ValueChanged<bool>    onShowTaxChanged;
  final ValueChanged<bool>    onShowQrChanged;
  final VoidCallback          onPickLogo;
  final VoidCallback          onSave;

  // Printer params
  final PrinterType                  printerType;
  final ReceiptPaperSize             paperSize;
  final TextEditingController        printerNameCtrl;
  final TextEditingController        printerIpCtrl;
  final TextEditingController        printerPortCtrl;
  final TextEditingController        btDeviceIdCtrl;
  final ValueChanged<PrinterType>    onPrinterTypeChanged;
  final ValueChanged<ReceiptPaperSize> onPaperSizeChanged;
  final bool                         isTesting;
  final VoidCallback                 onTestPrint;

  const _SettingsForm({
    required this.storeNameCtrl,
    required this.phoneCtrl,
    required this.addressCtrl,
    required this.footerCtrl,
    required this.footer2Ctrl,
    required this.showTax,
    required this.showQr,
    required this.logoPath,
    required this.onShowTaxChanged,
    required this.onShowQrChanged,
    required this.onPickLogo,
    required this.onSave,
    required this.printerType,
    required this.paperSize,
    required this.printerNameCtrl,
    required this.printerIpCtrl,
    required this.printerPortCtrl,
    required this.btDeviceIdCtrl,
    required this.onPrinterTypeChanged,
    required this.onPaperSizeChanged,
    required this.isTesting,
    required this.onTestPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Invoice settings title --------------------------------------
            _sectionHeader(
              context,
              icon:  Icons.settings_rounded,
              label: 'إعدادات الفاتورة',
              color: Theme.of(context).colorScheme.primaryContainer,
              iconColor: Theme.of(context).colorScheme.primary,
            ),

            const SizedBox(height: 20),

            TextField(
              controller: storeNameCtrl,
              decoration: const InputDecoration(
                labelText:  'اسم المحل',
                hintText:   'مثال: سوبر ماركت النجوم',
                border:     OutlineInputBorder(),
                prefixIcon: Icon(Icons.store_rounded),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller:   phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration:   const InputDecoration(
                labelText:  'رقم الهاتف',
                hintText:   'مثال: 07700000000',
                border:     OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_rounded),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                labelText:  'عنوان المحل',
                hintText:   'مثال: شارع السعدون، بغداد',
                border:     OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_rounded),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: footerCtrl,
              maxLines:   2,
              decoration: const InputDecoration(
                labelText:  'نص أسفل الفاتورة (السطر الأول)',
                hintText:   'مثال: شكراً لزيارتكم',
                border:     OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields_rounded),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: footer2Ctrl,
              decoration: const InputDecoration(
                labelText:  'نص إضافي (السطر الثاني)',
                hintText:   'مثال: نتمنى لكم يوماً سعيداً',
                border:     OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),

            const SizedBox(height: 12),

            _toggle(
              context,
              icon:      Icons.percent_rounded,
              title:     'إظهار الضريبة',
              subtitle:  'تضمين ضريبة 15% في الفاتورة',
              value:     showTax,
              onChanged: onShowTaxChanged,
            ),

            const SizedBox(height: 8),

            _toggle(
              context,
              icon:      Icons.qr_code_rounded,
              title:     'إظهار رمز QR',
              subtitle:  'إضافة رمز QR في أسفل الفاتورة',
              value:     showQr,
              onChanged: onShowQrChanged,
            ),

            const SizedBox(height: 20),

            // -- Printer settings section ------------------------------------
            const Divider(),
            const SizedBox(height: 12),

            _sectionHeader(
              context,
              icon:      Icons.print_rounded,
              label:     'إعدادات الطابعة',
              color:     Theme.of(context).colorScheme.secondaryContainer,
              iconColor: Theme.of(context).colorScheme.secondary,
            ),

            const SizedBox(height: 16),

            // Printer type
            DropdownButtonFormField<PrinterType>(
              key: ValueKey(printerType),
              initialValue: printerType,
              decoration: const InputDecoration(
                labelText:  'نوع الطابعة',
                border:     OutlineInputBorder(),
                prefixIcon: Icon(Icons.print_rounded),
              ),
              items: const [
                DropdownMenuItem(
                  value: PrinterType.pdf,
                  child: Text('طابعة عادية (PDF)'),
                ),
                DropdownMenuItem(
                  value: PrinterType.usbThermal,
                  child: Text('طابعة حرارية USB'),
                ),
                DropdownMenuItem(
                  value: PrinterType.lanThermal,
                  child: Text('طابعة حرارية شبكة (LAN)'),
                ),
                DropdownMenuItem(
                  value: PrinterType.bluetoothThermal,
                  child: Text('طابعة حرارية بلوتوث'),
                ),
              ],
              onChanged: (v) { if (v != null) onPrinterTypeChanged(v); },
            ),

            const SizedBox(height: 12),

            // Paper size
            DropdownButtonFormField<ReceiptPaperSize>(
              key: ValueKey(paperSize),
              initialValue: paperSize,
              decoration: const InputDecoration(
                labelText:  'حجم الورقة',
                border:     OutlineInputBorder(),
                prefixIcon: Icon(Icons.straighten_rounded),
              ),
              items: const [
                DropdownMenuItem(
                  value: ReceiptPaperSize.thermal58,
                  child: Text('58mm (حراري صغير)'),
                ),
                DropdownMenuItem(
                  value: ReceiptPaperSize.thermal80,
                  child: Text('80mm (حراري قياسي)'),
                ),
                DropdownMenuItem(
                  value: ReceiptPaperSize.a4,
                  child: Text('A4 (عادي)'),
                ),
              ],
              onChanged: (v) { if (v != null) onPaperSizeChanged(v); },
            ),

            // USB: printer name
            if (printerType == PrinterType.usbThermal) ...[
              const SizedBox(height: 12),
              TextField(
                controller: printerNameCtrl,
                decoration: const InputDecoration(
                  labelText:  'اسم الطابعة',
                  hintText:   'مثال: XP-T80',
                  border:     OutlineInputBorder(),
                  prefixIcon: Icon(Icons.usb_rounded),
                ),
              ),
            ],

            // LAN: IP + port
            if (printerType == PrinterType.lanThermal) ...[
              const SizedBox(height: 12),
              TextField(
                controller: printerIpCtrl,
                decoration: const InputDecoration(
                  labelText:  'عنوان IP الطابعة',
                  hintText:   'مثال: 192.168.1.100',
                  border:     OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lan_rounded),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller:       printerPortCtrl,
                keyboardType:     TextInputType.number,
                inputFormatters:  [FilteringTextInputFormatter.digitsOnly],
                decoration:       const InputDecoration(
                  labelText:  'المنفذ (Port)',
                  hintText:   '9100',
                  border:     OutlineInputBorder(),
                  prefixIcon: Icon(Icons.settings_ethernet_rounded),
                ),
              ),
            ],

            // Bluetooth: device id
            if (printerType == PrinterType.bluetoothThermal) ...[
              const SizedBox(height: 12),
              TextField(
                controller: btDeviceIdCtrl,
                decoration: const InputDecoration(
                  labelText:  'معرّف جهاز البلوتوث',
                  hintText:   'مثال: 00:11:22:33:44:55',
                  border:     OutlineInputBorder(),
                  prefixIcon: Icon(Icons.bluetooth_rounded),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Test print button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: isTesting ? null : onTestPrint,
                icon: isTesting
                    ? const SizedBox(
                        width:  18,
                        height: 18,
                        child:  CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined),
                label: Text(
                  isTesting ? 'جارٍ الطباعة...' : 'طباعة تجريبية',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // -- Logo picker -------------------------------------------------
            const Divider(),
            const SizedBox(height: 12),

            if (logoPath != null && logoPath!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(logoPath!),
                        height: 48,
                        width:  48,
                        fit:    BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        logoPath!.split(r'\').last,
                        style:    Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            OutlinedButton.icon(
              onPressed: onPickLogo,
              icon:      const Icon(Icons.image_rounded),
              label:     const Text('اختيار شعار المحل'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),

            const SizedBox(height: 24),

            // -- Save button -------------------------------------------------
            SizedBox(
              width:  double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: onSave,
                icon:  const Icon(Icons.save_rounded),
                label: const Text(
                  'حفظ الإعدادات',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Helpers ----------------------------------------------------------------

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String   label,
    required Color    color,
    required Color    iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding:    const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:        color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _toggle(
    BuildContext context, {
    required IconData         icon,
    required String           title,
    required String           subtitle,
    required bool             value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin:    EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SwitchListTile(
        title:     Text(title),
        subtitle:  Text(subtitle),
        value:     value,
        onChanged: onChanged,
        secondary: Icon(icon),
        dense:     true,
      ),
    );
  }
}
