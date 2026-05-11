import 'package:flutter/material.dart';
import '../../features/pos/models/invoice_models.dart';

class InvoicePreviewWidget extends StatelessWidget {
  final InvoiceData data;

  const InvoicePreviewWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            /// 🏪 HEADER
            Center(
              child: Text(
                data.storeName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if (data.phone != null) Center(child: Text(data.phone!)),

            const SizedBox(height: 8),

            /// 🧾 INFO
            Text("رقم الفاتورة: ${data.invoiceNumber}"),
            Text("التاريخ: ${data.date}"),

            const SizedBox(height: 8),

            /// 📦 ITEMS
            ...data.items.map((e) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(e.name)),
                  Text("${e.qty} x ${e.unitPrice}"),
                  Text("${e.lineTotal}"),
                ],
              );
            }),

            const Divider(),

            /// 💰 TOTAL
            Text(
              "الإجمالي: ${data.total}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            /// ❤️ FOOTER
            const Center(child: Text("شكراً لتعاملكم معنا")),
          ],
        ),
      ),
    );
  }
}
