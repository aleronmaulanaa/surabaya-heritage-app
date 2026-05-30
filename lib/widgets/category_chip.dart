import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../utils/constants.dart';

class CategoryChip extends StatelessWidget {
  final CategoryModel category;
  final bool          isSelected;
  final VoidCallback  onTap;

  const CategoryChip({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(
      AppConstants.categoryColors[category.name] ?? 0xFF1E3A5F,
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin:  const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color:        isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: color, width: 1.5),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8)]
              : [],
        ),
        child: Text(
          category.name,
          style: TextStyle(
            color:      isSelected ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize:   13,
          ),
        ),
      ),
    );
  }
}