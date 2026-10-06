import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/expense_creation_service.dart';

final expenseCreationServiceProvider = Provider<ExpenseCreationService>((ref) {
  return ExpenseCreationService(AppDatabase.instance);
});