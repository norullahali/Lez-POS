// lib/features/returns/utils/supplier_refund_settlement_messages.dart

import '../../../core/services/supplier_refund_settlement_service.dart';

String supplierRefundSettlementFailureMessage(
  SupplierRefundSettlementFailure code,
) {
  switch (code) {
    case SupplierRefundSettlementFailure.supplierNotFound:
      return 'المورد غير موجود';
    case SupplierRefundSettlementFailure.noSupplierCredit:
      return 'لا يوجد رصيد دائن متاح لهذا المورد';
    case SupplierRefundSettlementFailure.invalidAmount:
      return 'مبلغ الاسترداد غير صالح';
    case SupplierRefundSettlementFailure.amountExceedsCredit:
      return 'مبلغ الاسترداد يتجاوز الرصيد الدائن المتاح';
    case SupplierRefundSettlementFailure.returnNotFound:
      return 'مرتجع المورد غير موجود';
    case SupplierRefundSettlementFailure.returnSupplierMismatch:
      return 'المرتجع لا ينتمي إلى هذا المورد';
    case SupplierRefundSettlementFailure.unexpectedFailure:
      return 'تعذر إتمام استرداد المبلغ';
  }
}
