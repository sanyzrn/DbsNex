import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

class ParkingTextField extends StatelessWidget {
  const ParkingTextField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.hint,
    this.minLines = 2,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final String? hint;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => NexTextField(
    controller: controller,
    decoration: decoration.copyWith(hintText: hint ?? decoration.hintText),
    onChanged: onChanged,
    enabled: enabled,
    minLines: minLines,
    maxLines: 5,
  );
}
