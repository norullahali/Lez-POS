import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lez_pos/core/utils/receipt_money_format.dart';

void main() {
  group('ReceiptMoneyFormat', () {
    final invoiceDetailMoney = NumberFormat('#,##0.##');

    test('integer IQD amounts match invoice detail UI pattern', () {
      expect(ReceiptMoneyFormat.formatAmount(15000),
          invoiceDetailMoney.format(15000));
      expect(ReceiptMoneyFormat.formatIqd(15000),
          '${invoiceDetailMoney.format(15000)} د.ع');
    });

    test('fractional amounts preserve up to two decimal places', () {
      expect(ReceiptMoneyFormat.formatAmount(13.5),
          invoiceDetailMoney.format(13.5));
      expect(ReceiptMoneyFormat.formatAmount(13.575),
          invoiceDetailMoney.format(13.575));
    });

    test('display tax amount matches detail UI for netBeforeTax * 0.15', () {
      const netBeforeTax = 90.5;
      final tax = netBeforeTax * 0.15;
      expect(
        ReceiptMoneyFormat.formatAmount(tax),
        invoiceDetailMoney.format(tax),
      );
    });
  });
}
