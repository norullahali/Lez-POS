// lib/features/returns/providers/partial_return_provider.dart
//
// Riverpod provider that exposes PartialReturnService to the widget tree.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/partial_return_service.dart';

final partialReturnServiceProvider = Provider<PartialReturnService>((ref) {
  return PartialReturnService(AppDatabase.instance);
});