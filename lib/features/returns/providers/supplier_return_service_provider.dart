// lib/features/returns/providers/supplier_return_service_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/supplier_return_service.dart';

/// Canonical SR.2 posting service for purchase-linked supplier returns.
final supplierReturnServiceProvider = Provider<SupplierReturnService>((ref) {
  return SupplierReturnService(AppDatabase.instance);
});

/// Incremented after a successful post so the returns screen can refresh.
final supplierReturnsRefreshProvider = StateProvider<int>((ref) => 0);
