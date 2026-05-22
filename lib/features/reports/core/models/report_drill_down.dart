enum ReportDrillDownEntityType {
  product,
  customer,
  supplier,
  invoice,
  invoiceHistory,
  user,
}

class ReportDrillDownTarget {
  const ReportDrillDownTarget({
    required this.type,
    required this.id,
    this.label,
  });

  final ReportDrillDownEntityType type;
  final int id;
  final String? label;
}