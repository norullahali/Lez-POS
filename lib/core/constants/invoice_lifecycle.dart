/// Values for `sales_invoices.invoice_status`.
class InvoiceLifecycleStatus {
  InvoiceLifecycleStatus._();

  static const completed = 'completed';
  static const returned = 'returned';
}

String invoiceLifecycleLabelAr(String code) {
  switch (code) {
    case InvoiceLifecycleStatus.returned:
      return 'مرتجعة';
    default:
      return 'مكتملة';
  }
}

bool invoiceIsReturned(String status) =>
    status == InvoiceLifecycleStatus.returned;
