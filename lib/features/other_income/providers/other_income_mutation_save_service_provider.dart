import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/other_income_mutation_save_service.dart';

final otherIncomeMutationSaveServiceProvider =
    Provider<OtherIncomeMutationSaveService>((ref) {
  return OtherIncomeMutationSaveService(AppDatabase.instance);
});
