import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CustomDataTable extends StatelessWidget {
  final List<String> columns;
  final List<DataRow> rows;
  final double? columnSpacing;

  const CustomDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.columnSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: columnSpacing ?? 24.0,
          headingRowColor: WidgetStateProperty.all(AppColors.background),
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.text,
          ),
          columns: columns
              .map((c) => DataColumn(
                    label: Text(
                      c,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ))
              .toList(),
          rows: rows,
        ),
      ),
    );
  }
}
