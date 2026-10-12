import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/expense_mutation_save_service.dart';

final expenseMutationSaveServiceProvider =
    Provider<ExpenseMutationSaveService>((ref) {
  return ExpenseMutationSaveService(AppDatabase.instance);
});
