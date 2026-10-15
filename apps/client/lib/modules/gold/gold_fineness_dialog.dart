import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'gold_format.dart';
import 'gold_strings.dart';

Future<int?> showGoldFinenessDialog(BuildContext context, int current) =>
    nexShowDialog<int>(
      context: context,
      builder: (_) => _FinenessDialog(current: current),
    );

class _FinenessDialog extends StatefulWidget {
  const _FinenessDialog({required this.current});
  final int current;
  @override
  State<_FinenessDialog> createState() => _FinenessDialogState();
}

class _FinenessDialogState extends State<_FinenessDialog> {
  late final _controller = TextEditingController(text: '${widget.current}');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NexAlertDialog(
    title: Text(goldStrings(context, 'finenessCustom')),
    content: NexDialogBody(
      child: Form(
        key: _form,
        child: TextFormField(
          key: const ValueKey('gold-fineness-custom-field'),
          controller: _controller,
          autofocus: true,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(counterText: '', errorMaxLines: 3),
          validator: (text) {
            final (value, problem) = parseScaledDetailed(text ?? '', 0);
            return problem != null ||
                    value == null ||
                    value < 100 ||
                    value > 999
                ? goldStrings(context, 'problem_fineness')
                : null;
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('gold-fineness-custom-cancel'),
        onPressed: () => Navigator.pop(context),
        child: Text(AppLocalizations.of(context).cancel),
      ),
      TextButton(
        key: const ValueKey('gold-fineness-custom-ok'),
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, parseScaled(_controller.text, 0));
          }
        },
        child: Text(AppLocalizations.of(context).save),
      ),
    ],
  );
}
