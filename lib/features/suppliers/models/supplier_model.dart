// lib/features/suppliers/models/supplier_model.dart

class SupplierModel {
  final int? id;
  final String name;
  final String phone;
  final String address;
  final String notes;
  final bool isActive;

  const SupplierModel({
    this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.isActive = true,
  });

  SupplierModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    String? notes,
    bool? isActive,
  }) {
    return SupplierModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
    );
  }
}
