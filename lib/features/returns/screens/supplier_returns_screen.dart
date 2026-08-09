import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/supplier_return_service_provider.dart';
import 'widgets/create_supplier_return_dialog.dart';

class SupplierReturnsScreen extends ConsumerStatefulWidget {
  const SupplierReturnsScreen({super.key});

  @override
  ConsumerState<SupplierReturnsScreen> createState() =>
      _SupplierReturnsScreenState();
}

class _SupplierReturnsScreenState extends ConsumerState<SupplierReturnsScreen> {
  bool _createDialogOpen = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(supplierReturnsRefreshProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(children: [
            const Text('مرتجعات الموردين',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const Spacer(),
            ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('مرتجع مورد'),
                onPressed:
                    _createDialogOpen ? null : _openCreateSupplierReturnDialog),
          ]),
          const SizedBox(height: 16),
          const Expanded(
            child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.local_shipping_outlined,
                      size: 64, color: AppColors.textHint),
                  SizedBox(height: 16),
                  Text('لا توجد مرتجعات موردين',
                      style: TextStyle(color: AppColors.textHint)),
                ])),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateSupplierReturnDialog() async {
    if (_createDialogOpen) return;
    setState(() => _createDialogOpen = true);
    final posted = await showCreateSupplierReturnDialog(context, ref);
    if (mounted) {
      setState(() => _createDialogOpen = false);
      if (posted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حفظ مرتجع المورد بنجاح',
              textDirection: TextDirection.rtl,
            ),
          ),
        );
      }
    }
  }
}
