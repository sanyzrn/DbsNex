import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

/// Keeps the toggle visible above the optional fields.
class GoldDetails extends StatelessWidget {
  const GoldDetails({
    super.key,
    required this.open,
    required this.onChanged,
    required this.title,
    required this.child,
    this.hint,
    this.toggleKey,
  });
  final bool open;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? hint;
  final Key? toggleKey;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (open) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: toggleKey,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_outlined),
            title: Text(title),
            trailing: const Icon(Icons.expand_less),
            onTap: () {
              FocusScope.of(context).unfocus();
              onChanged(false);
            },
          ),
          child,
        ],
      );
    }
    return NexMoreDetails(
      open: open,
      onChanged: onChanged,
      title: title,
      hint: hint,
      toggleKey: toggleKey,
      child: child,
    );
  }
}
