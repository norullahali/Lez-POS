// lib/features/categories/models/category_model.dart
import 'package:flutter/material.dart';

class CategoryModel {
  final int? id;
  final String name;
  final String description;
  final int colorValue;
  final String icon;
  final bool isActive;

  const CategoryModel({
    this.id,
    required this.name,
    this.description = '',
    this.colorValue = 0xFF1565C0,
    this.icon = 'category',
    this.isActive = true,
  });

  Color get color => Color(colorValue);

  CategoryModel copyWith({
    int? id,
    String? name,
    String? description,
    int? colorValue,
    String? icon,
    bool? isActive,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      colorValue: colorValue ?? this.colorValue,
      icon: icon ?? this.icon,
      isActive: isActive ?? this.isActive,
    );
  }
}
