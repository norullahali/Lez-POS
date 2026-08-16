import '../database/app_database.dart';

class CustomerReturnCredit {
  CustomerReturnCredit._();

  static double goodsValueForReturnedQuantity({
    required double soldQuantity,
    required double lineTotal,
    required double returnedQuantity,
  }) {
    if (soldQuantity <= 0 || returnedQuantity <= 0 || lineTotal <= 0) return 0;
    return (returnedQuantity / soldQuantity) * lineTotal;
  }

  static double creditReversalForGoodsValue({
    required double returnedGoodsValue,
    required double invoiceTotal,
    required double invoiceDebtAmount,
  }) {
    if (invoiceDebtAmount <= 0 ||
        returnedGoodsValue <= 0 ||
        invoiceTotal <= 0) {
      return 0;
    }
    return returnedGoodsValue * (invoiceDebtAmount / invoiceTotal);
  }

  static double creditReversalForSaleLines({
    required SalesInvoice invoice,
    required List<SaleItem> saleLines,
    required Map<int, double> returnedQtyBySaleItemId,
  }) {
    var goodsValue = 0.0;
    for (final entry in returnedQtyBySaleItemId.entries) {
      if (entry.value <= 0) continue;
      final line = saleLines.firstWhere((l) => l.id == entry.key);
      goodsValue += goodsValueForReturnedQuantity(
        soldQuantity: line.quantity,
        lineTotal: line.total,
        returnedQuantity: entry.value,
      );
    }
    return creditReversalForGoodsValue(
      returnedGoodsValue: goodsValue,
      invoiceTotal: invoice.total,
      invoiceDebtAmount: invoice.debtAmount,
    );
  }

  static double cappedCreditReversal({
    required double proposed,
    required double invoiceDebtAmount,
    required double alreadyReversed,
  }) {
    if (proposed <= 0 || invoiceDebtAmount <= 0) return 0;
    final remaining = invoiceDebtAmount - alreadyReversed;
    if (remaining <= 0.0001) return 0;
    return proposed > remaining + 0.0001 ? remaining : proposed;
  }
}
