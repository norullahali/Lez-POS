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
  final _footerCtrl = TextEditingController();

  bool showTax = true;
  String? logoPath;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Trigger rebuild on every keystroke so the live preview updates instantly.
    _storeNameCtrl.addListener(_onFieldChanged);
    _footerCtrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _storeNameCtrl.removeListener(_onFieldChanged);
    _footerCtrl.removeListener(_onFieldChanged);
    _storeNameCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    logoPath = prefs.getString('store_logo');
    _storeNameCtrl.text = prefs.getString('store_name') ?? '';
    _footerCtrl.text = prefs.getString('invoice_footer') ?? '';
    showTax = prefs.getBool('show_tax') ?? true;
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (logoPath != null) await prefs.setString('store_logo', logoPath!);
    await prefs.setString('store_name', _storeNameCtrl.text);
    await prefs.setString('invoice_footer', _footerCtrl.text);
    await prefs.setBool('show_tax', showTax);
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
            width: 400,
            child: _SettingsForm(
              storeNameCtrl: _storeNameCtrl,
              footerCtrl: _footerCtrl,
              showTax: showTax,
              logoPath: logoPath,
              onShowTaxChanged: (v) => setState(() => showTax = v),
              onPickLogo: _pickLogo,
              onSave: _saveSettings,
            ),
          ),

          const SizedBox(width: 28),

          // ── Right column: live preview ────────────────────────────────────
          // Injected here — updates in real time as settings change.
          Expanded(
            child: InvoiceLivePreview(
              storeName: _storeNameCtrl.text,
              footerText: _footerCtrl.text,
              showTax: showTax,
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
  final TextEditingController footerCtrl;
  final bool showTax;
  final String? logoPath;
  final ValueChanged<bool> onShowTaxChanged;
  final VoidCallback onPickLogo;
  final VoidCallback onSave;

  const _SettingsForm({
    required this.storeNameCtrl,
    required this.footerCtrl,
    required this.showTax,
    required this.logoPath,
    required this.onShowTaxChanged,
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

            const SizedBox(height: 24),

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

            const SizedBox(height: 16),

            // ── Footer text ─────────────────────────────────────────────────
            TextField(
              controller: footerCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'نص أسفل الفاتورة',
                hintText: 'مثال: شكراً لزيارتكم، نتمنى لكم يوماً سعيداً',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields_rounded),
              ),
            ),

            const SizedBox(height: 8),

            // ── Show tax toggle ─────────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: SwitchListTile(
                title: const Text('إظهار الضريبة'),
                subtitle: const Text('تضمين ضريبة 15% في الفاتورة'),
                value: showTax,
                onChanged: onShowTaxChanged,
                secondary: const Icon(Icons.percent_rounded),
              ),
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
}
