import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

class MedicineTextField extends StatelessWidget {
  const MedicineTextField({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 2,
  });

  final TextEditingController controller;
  final String? hint;
  final int minLines;

  @override
  Widget build(BuildContext context) => NexTextField(
    controller: controller,
    decoration: InputDecoration(hintText: hint),
    minLines: minLines,
    maxLines: 5,
  );
}
