// Values for sales_invoices.invoice_status.
class InvoiceLifecycleStatus {
  InvoiceLifecycleStatus._();

  static const completed        = 'completed';
  static const partiallyReturned = 'partially_returned';
  static const returned         = 'returned';

  static const all = [completed, partiallyReturned, returned];
}

String invoiceLifecycleLabelAr(String code) {
  switch (code) {
    case InvoiceLifecycleStatus.partiallyReturned:
      return 'مرتجع جزئي';
    case InvoiceLifecycleStatus.returned:
      return 'مرتجع';
    default:
      return 'مكتملة';
  }
}

bool invoiceIsReturned(String status) =>
    status == InvoiceLifecycleStatus.returned;

bool invoiceHasAnyReturn(String status) =>
    status == InvoiceLifecycleStatus.returned ||
    status == InvoiceLifecycleStatus.partiallyReturned;

bool invoiceCanBeReturned(String status) =>
    status != InvoiceLifecycleStatus.returned;