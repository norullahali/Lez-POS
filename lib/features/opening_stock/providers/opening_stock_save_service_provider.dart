import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/opening_stock_save_service.dart';

final openingStockSaveServiceProvider = Provider<OpeningStockSaveService>((ref) {
  return OpeningStockSaveService(AppDatabase.instance);
});
