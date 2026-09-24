import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

class MkesTextField extends StatefulWidget {
  const MkesTextField({
    super.key,
    this.label,
    required this.controller,
    this.hintText,
    this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.validator,
    this.enabled,
    this.onChanged,
    this.maxLines = 1,
  });

  final String? label;
  final TextEditingController controller;
  final String? hintText;
  final IconData? prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final bool? enabled;
  final void Function(String)? onChanged;
  final int? maxLines;

  @override
  State<MkesTextField> createState() => _MkesTextFieldState();
}

class _MkesTextFieldState extends State<MkesTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor =
        _focused ? AppColors.primaryContainer : AppColors.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          obscureText: widget.obscureText,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          enabled: widget.enabled,
          onChanged: widget.onChanged,
          style: AppTypography.bodyMd,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, color: iconColor, size: 20)
                : null,
            suffixIcon: widget.suffix,
            fillColor: _focused
                ? AppColors.surfaceContainerLowest
                : AppColors.surfaceContainerLow,
          ),
        ),
      ],
    );
  }
}
