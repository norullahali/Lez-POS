// lib/features/purchases/providers/purchases_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../models/purchase_invoice_model.dart';
import '../repositories/purchases_repository.dart';
import '../../auth/providers/auth_provider.dart';

final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  return PurchasesRepository(AppDatabase.instance);
});

final purchasesStreamProvider = StreamProvider<List<PurchaseInvoiceModel>>((ref) {
  return ref.watch(purchasesRepositoryProvider).watchAll();
});

class PurchasesNotifier extends AsyncNotifier<List<PurchaseInvoiceModel>> {
  @override
  Future<List<PurchaseInvoiceModel>> build() async {
    try {
      debugPrint('[PurchasesNotifier] build: loading purchase invoices...');
      final result = await ref.watch(purchasesRepositoryProvider).getAll();
      debugPrint('[PurchasesNotifier] build: loaded ${result.length} invoices.');
      return result;
    } catch (e, st) {
      debugPrint('[PurchasesNotifier] build error: $e\n$st');
      rethrow;
    }
  }

  Future<int> save(PurchaseInvoiceModel invoice) async {
    try {
      final userId = ref.read(authProvider).valueOrNull?.user?.id;
      final id = await ref.read(purchasesRepositoryProvider).save(invoice, userId);
      ref.invalidateSelf();
      return id;
    } catch (e, st) {
      debugPrint('[PurchasesNotifier] save error: $e\n$st');
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      await ref.read(purchasesRepositoryProvider).delete(id);
      ref.invalidateSelf();
    } catch (e, st) {
      debugPrint('[PurchasesNotifier] delete error: $e\n$st');
      rethrow;
    }
  }
}

final purchasesNotifierProvider =
    AsyncNotifierProvider<PurchasesNotifier, List<PurchaseInvoiceModel>>(PurchasesNotifier.new);

// Form state for new purchase invoice
class PurchaseFormState {
  final int? supplierId;
  final String supplierName;
  final String invoiceNumber;
  final DateTime date;
  final List<PurchaseItemModel> items;
  final double invoiceDiscount;
  final String notes;
  final double paidAmount;
  final DateTime? dueDate;

  const PurchaseFormState({
    this.supplierId,
    this.supplierName = '',
    this.invoiceNumber = '',
    required this.date,
    this.items = const [],
    this.invoiceDiscount = 0,
    this.notes = '',
    this.paidAmount = 0,
    this.dueDate,
  });

  double get subtotal => items.fold(0.0, (s, i) => s + (i.quantity * i.unitCost));
  double get total => subtotal - invoiceDiscount;

  PurchaseFormState copyWith({
    int? supplierId,
    String? supplierName,
    String? invoiceNumber,
    DateTime? date,
    List<PurchaseItemModel>? items,
    double? invoiceDiscount,
    String? notes,
    double? paidAmount,
    DateTime? dueDate,
  }) {
    return PurchaseFormState(
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      date: date ?? this.date,
      items: items ?? this.items,
      invoiceDiscount: invoiceDiscount ?? this.invoiceDiscount,
      notes: notes ?? this.notes,
      paidAmount: paidAmount ?? this.paidAmount,
      dueDate: dueDate ?? this.dueDate,
    );
  }
}

class PurchaseFormNotifier extends Notifier<PurchaseFormState> {
  @override
  PurchaseFormState build() => PurchaseFormState(date: DateTime.now());

  void reset() => state = PurchaseFormState(date: DateTime.now());
  void setSupplier(int? id, String name) => state = state.copyWith(supplierId: id, supplierName: name);
  void setInvoiceNumber(String v) => state = state.copyWith(invoiceNumber: v);
  void setDate(DateTime d) => state = state.copyWith(date: d);
  void setDiscount(double d) => state = state.copyWith(invoiceDiscount: d);
  void setNotes(String n) => state = state.copyWith(notes: n);
  void setPaidAmount(double a) => state = state.copyWith(paidAmount: a);
  void setDueDate(DateTime? d) => state = state.copyWith(dueDate: d);

  void addItem(PurchaseItemModel item) {
    final existing = state.items.indexWhere((i) => i.productId == item.productId);
    if (existing >= 0) {
      final items = [...state.items];
      items[existing] = items[existing].copyWith(quantity: items[existing].quantity + item.quantity);
      state = state.copyWith(items: items);
    } else {
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  void updateItem(int index, PurchaseItemModel item) {
    final items = [...state.items];
    items[index] = item;
    state = state.copyWith(items: items);
  }

  void removeItem(int index) {
    final items = [...state.items]..removeAt(index);
    state = state.copyWith(items: items);
  }
}

final purchaseFormProvider = NotifierProvider<PurchaseFormNotifier, PurchaseFormState>(PurchaseFormNotifier.new);
