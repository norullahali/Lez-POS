import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/invoice_live_preview.dart';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  final _storeNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _footer2Ctrl = TextEditingController();

  bool showTax = true;
  bool showQr = false;
  String? logoPath;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Rebuild on every keystroke so the live preview updates instantly.
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
    ]) {
      c.removeListener(_onFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    logoPath = prefs.getString('store_logo');
    _storeNameCtrl.text = prefs.getString('store_name') ?? '';
    _phoneCtrl.text = prefs.getString('store_phone') ?? '';
    _addressCtrl.text = prefs.getString('store_address') ?? '';
    _footerCtrl.text = prefs.getString('invoice_footer') ?? '';
    _footer2Ctrl.text = prefs.getString('invoice_footer2') ?? '';
    showTax = prefs.getBool('show_tax') ?? true;
    showQr = prefs.getBool('show_qr') ?? false;
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (logoPath != null) await prefs.setString('store_logo', logoPath!);
    await prefs.setString('store_name', _storeNameCtrl.text);
    await prefs.setString('store_phone', _phoneCtrl.text);
    await prefs.setString('store_address', _addressCtrl.text);
    await prefs.setString('invoice_footer', _footerCtrl.text);
    await prefs.setString('invoice_footer2', _footer2Ctrl.text);
    await prefs.setBool('show_tax', showTax);
    await prefs.setBool('show_qr', showQr);
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left column: settings form ────────────────────────────────────
          SizedBox(
            width: 420,
            child: _SettingsForm(
              storeNameCtrl: _storeNameCtrl,
              phoneCtrl: _phoneCtrl,
              addressCtrl: _addressCtrl,
              footerCtrl: _footerCtrl,
              footer2Ctrl: _footer2Ctrl,
              showTax: showTax,
              showQr: showQr,
              logoPath: logoPath,
              onShowTaxChanged: (v) => setState(() => showTax = v),
              onShowQrChanged: (v) => setState(() => showQr = v),
              onPickLogo: _pickLogo,
              onSave: _saveSettings,
            ),
          ),

          const SizedBox(width: 28),

          // Right column: live preview — updates in real time as fields change.
          Expanded(
            child: InvoiceLivePreview(
              storeName: _storeNameCtrl.text,
              phone: _phoneCtrl.text,
              address: _addressCtrl.text,
              footerText: _footerCtrl.text,
              footerText2: _footer2Ctrl.text,
              showTax: showTax,
              showQr: showQr,
              logoPath: logoPath,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings form extracted to a StatelessWidget to keep build() clean
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsForm extends StatelessWidget {
  final TextEditingController storeNameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController footerCtrl;
  final TextEditingController footer2Ctrl;
  final bool showTax;
  final bool showQr;
  final String? logoPath;
  final ValueChanged<bool> onShowTaxChanged;
  final ValueChanged<bool> onShowQrChanged;
  final VoidCallback onPickLogo;
  final VoidCallback onSave;

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
            // ── Section title ───────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'إعدادات الفاتورة',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Store name ──────────────────────────────────────────────────
            TextField(
              controller: storeNameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم المحل',
                hintText: 'مثال: سوبر ماركت النجوم',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store_rounded),
              ),
            ),

            const SizedBox(height: 12),

            // ── Phone number ────────────────────────────────────────────────
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                hintText: 'مثال: 07700000000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_rounded),
              ),
            ),

            const SizedBox(height: 12),

            // ── Store address ───────────────────────────────────────────────
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                labelText: 'عنوان المحل',
                hintText: 'مثال: شارع السعدون، بغداد',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_rounded),
              ),
            ),

            const SizedBox(height: 12),

            // ── Footer line 1 ───────────────────────────────────────────────
            TextField(
              controller: footerCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'نص أسفل الفاتورة (السطر الأول)',
                hintText: 'مثال: شكراً لزيارتكم',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields_rounded),
              ),
            ),

            const SizedBox(height: 12),

            // ── Footer line 2 (extra) ───────────────────────────────────────
            TextField(
              controller: footer2Ctrl,
              decoration: const InputDecoration(
                labelText: 'نص إضافي (السطر الثاني)',
                hintText: 'مثال: نتمنى لكم يوماً سعيداً',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),

            const SizedBox(height: 12),

            // ── Toggles group ───────────────────────────────────────────────
            _toggle(
              context,
              icon: Icons.percent_rounded,
              title: 'إظهار الضريبة',
              subtitle: 'تضمين ضريبة 15% في الفاتورة',
              value: showTax,
              onChanged: onShowTaxChanged,
            ),
            const SizedBox(height: 8),
            _toggle(
              context,
              icon: Icons.qr_code_rounded,
              title: 'إظهار رمز QR',
              subtitle: 'إضافة رمز QR في أسفل الفاتورة',
              value: showQr,
              onChanged: onShowQrChanged,
            ),

            const SizedBox(height: 16),

            // ── Printer type ────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: 'pdf',
              decoration: const InputDecoration(
                labelText: 'نوع الطابعة',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.print_rounded),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'pdf', child: Text('طابعة عادية (PDF)')),
                DropdownMenuItem(
                    value: 'thermal', child: Text('طابعة حرارية')),
              ],
              onChanged: (value) async {
                if (value == null) return;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('printer_type', value);
              },
            ),

            const SizedBox(height: 16),

            // ── Logo picker ─────────────────────────────────────────────────
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
                        width: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        logoPath!.split(r'\').last,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            OutlinedButton.icon(
              onPressed: onPickLogo,
              icon: const Icon(Icons.image_rounded),
              label: const Text('اختيار شعار المحل'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),

            const SizedBox(height: 24),

            // ── Save button ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_rounded),
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

  Widget _toggle(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon),
        dense: true,
      ),
    );
  }
}
