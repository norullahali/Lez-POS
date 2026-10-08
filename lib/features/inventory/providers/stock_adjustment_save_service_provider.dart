import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/stock_adjustment_save_service.dart';

final stockAdjustmentSaveServiceProvider =
    Provider<StockAdjustmentSaveService>((ref) {
  return StockAdjustmentSaveService(AppDatabase.instance);
});
