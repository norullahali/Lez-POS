// lib/features/pos/screens/widgets/customer_selection_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../customers/providers/customers_provider.dart';

class CustomerSelectionModal extends ConsumerStatefulWidget {
  const CustomerSelectionModal({super.key});

  @override
  ConsumerState<CustomerSelectionModal> createState() => _CustomerSelectionModalState();
}

class _CustomerSelectionModalState extends ConsumerState<CustomerSelectionModal> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersStreamProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.posPanel,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('اختيار العميل', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'ابحث عن عميل...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
              filled: true,
              fillColor: AppColors.posPanelLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: customersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('خطأ: $err', style: const TextStyle(color: AppColors.error))),
              data: (customers) {
                // Filter active customers
                final active = customers.where((c) => c.isActive).toList();
                
                final filtered = active.where((c) {
                  if (_searchQuery.isEmpty) return true;
                  final sq = _searchQuery.toLowerCase();
                  return c.name.toLowerCase().contains(sq) ||
                      (c.phone?.toLowerCase().contains(sq) ?? false);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('لا يوجد عملاء مطابقين', style: TextStyle(color: Colors.white54)));
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (context, index) {
                    final c = filtered[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: c.id == 1 ? AppColors.accent : AppColors.posPanelLight,
                        child: Icon(c.id == 1 ? Icons.storefront_rounded : Icons.person_rounded, color: Colors.white, size: 20),
                      ),
                      title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: c.phone != null ? Text(c.phone!, style: const TextStyle(color: Colors.white54)) : null,
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
