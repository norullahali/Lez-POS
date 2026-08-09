// lib/features/returns/utils/supplier_return_posting_messages.dart

import '../../../core/services/supplier_return_service.dart';

String supplierReturnPostingFailureMessage(SupplierReturnPostingFailure code) {
  switch (code) {
    case SupplierReturnPostingFailure.purchaseNotFound:
      return 'فاتورة الشراء غير موجودة';
    case SupplierReturnPostingFailure.supplierNotFound:
      return 'المورد غير موجود';
    case SupplierReturnPostingFailure.supplierMismatch:
      return 'المورد لا يطابق فاتورة الشراء';
    case SupplierReturnPostingFailure.emptyLines:
      return 'يجب تحديد بنود للإرجاع';
    case SupplierReturnPostingFailure.purchaseItemNotFound:
      return 'بند الشراء غير موجود';
    case SupplierReturnPostingFailure.purchaseItemInvoiceMismatch:
      return 'بند الشراء لا ينتمي إلى هذه الفاتورة';
    case SupplierReturnPostingFailure.invalidQuantity:
      return 'كمية الإرجاع غير صالحة';
    case SupplierReturnPostingFailure.quantityExceedsReturnable:
      return 'الكمية تتجاوز المتاح للإرجاع';
    case SupplierReturnPostingFailure.stockInsufficient:
      return 'تعذر خصم الكمية من المخزون';
    case SupplierReturnPostingFailure.supplierAccountingFailure:
      return 'تعذر تسجيل حركة المورد';
  }
}
