// lib/core/services/customer_invoice_return_posting_result.dart

enum CustomerInvoiceReturnType {
  partial,
  full,
}

enum CustomerInvoiceExecutionPath {
  partialBatch('partial_batch'),
  fullFresh('full_fresh'),
  fullRemaining('full_remaining');

  const CustomerInvoiceExecutionPath(this.code);
  final String code;

  static CustomerInvoiceExecutionPath fromCode(String code) {
    return CustomerInvoiceExecutionPath.values.firstWhere(
      (value) => value.code == code,
      orElse: () => CustomerInvoiceExecutionPath.partialBatch,
    );
  }
}

class CustomerInvoicePartialReturnExecution {
  const CustomerInvoicePartialReturnExecution({
    required this.customerReturnId,
    required this.primaryReferenceId,
  });

  final int customerReturnId;
  final int primaryReferenceId;
}

class CustomerInvoiceReturnPostingResult {
  const CustomerInvoiceReturnPostingResult({
    required this.customerReturnId,
    required this.returnType,
    required this.executionPath,
    required this.primaryReferenceId,
    required this.idempotentReplay,
  });

  final int? customerReturnId;
  final CustomerInvoiceReturnType returnType;
  final CustomerInvoiceExecutionPath executionPath;
  final int? primaryReferenceId;
  final bool idempotentReplay;
}