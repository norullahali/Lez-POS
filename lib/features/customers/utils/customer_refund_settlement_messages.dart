// lib/features/customers/utils/customer_refund_settlement_messages.dart

import '../../../core/services/customer_refund_settlement_service.dart';

String customerRefundSettlementFailureMessage(
  CustomerRefundSettlementFailure code,
) {
  switch (code) {
    case CustomerRefundSettlementFailure.customerNotFound:
      return 'العميل غير موجود';
    case CustomerRefundSettlementFailure.noCustomerCredit:
      return 'لا يوجد رصيد دائن متاح لهذا العميل';
    case CustomerRefundSettlementFailure.invalidAmount:
      return 'مبلغ الاسترداد غير صالح';
    case CustomerRefundSettlementFailure.amountExceedsCredit:
      return 'مبلغ الاسترداد يتجاوز الرصيد الدائن المتاح';
    case CustomerRefundSettlementFailure.returnNotFound:
      return 'مرتجع العميل غير موجود';
    case CustomerRefundSettlementFailure.returnCustomerMismatch:
      return 'المرتجع لا ينتمي إلى هذا العميل';
    case CustomerRefundSettlementFailure.unexpectedFailure:
      return 'تعذر إتمام استرداد المبلغ';
  }
}
