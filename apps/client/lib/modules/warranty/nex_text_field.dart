import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

class WarrantyTextField extends StatelessWidget {
  const WarrantyTextField({
    super.key,
    required this.controller,
    this.hint,
    this.helper,
    this.minLines = 2,
  });

  final TextEditingController controller;
  final String? hint;

  /// An error or note under the field, shown after a failed save.
  final String? helper;
  final int minLines;

  @override
  Widget build(BuildContext context) => NexTextField(
    controller: controller,
    decoration: InputDecoration(hintText: hint, helperText: helper),
    minLines: minLines,
    maxLines: 5,
  );
}
