// lib/core/widgets/search_field.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final VoidCallback? onSubmitted;

  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.focusNode,
    this.controller,
    this.onSubmitted,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textHint),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              ),
      ),
    );
  }
}
