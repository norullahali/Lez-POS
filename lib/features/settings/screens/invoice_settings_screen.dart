import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  final _storeNameCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();

  bool showTax = true;
  String? logoPath; // ✅ مهم جداً

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

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

    if (logoPath != null) {
      await prefs.setString('store_logo', logoPath!);
    }

    await prefs.setString('store_name', _storeNameCtrl.text);
    await prefs.setString('invoice_footer', _footerCtrl.text);
    await prefs.setBool('show_tax', showTax);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الحفظ بنجاح')),
    );
  }

  // ✅ اختيار الشعار
  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        logoPath = result.files.single.path!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إعدادات الفاتورة',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 24),

                  TextField(
                    controller: _storeNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المحل',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: _footerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'نص أسفل الفاتورة',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SwitchListTile(
                    title: const Text('إظهار الضريبة'),
                    value: showTax,
                    onChanged: (v) => setState(() => showTax = v),
                  ),

                  const SizedBox(height: 20),

                  DropdownButtonFormField<String>(
                    value: 'pdf',
                    decoration: const InputDecoration(
                      labelText: 'نوع الطابعة',
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

                  /// ✅ زر اختيار الشعار (داخل Column)
                  ElevatedButton(
                    onPressed: _pickLogo,
                    child: const Text('اختيار شعار المحل'),
                  ),

                  const SizedBox(height: 24),

                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('حفظ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
