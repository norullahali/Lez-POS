// lib/features/returns/providers/manual_return_service_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/manual_return_service.dart';

final manualReturnServiceProvider = Provider<ManualReturnService>((ref) {
  return ManualReturnService(AppDatabase.instance);
});
