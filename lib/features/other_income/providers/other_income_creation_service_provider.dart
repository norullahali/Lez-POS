import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/other_income_creation_service.dart';

final otherIncomeCreationServiceProvider =
    Provider<OtherIncomeCreationService>((ref) {
  return OtherIncomeCreationService(AppDatabase.instance);
});