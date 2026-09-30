import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Nex's mark and wordmark, drawn from the designer's own vectors.
///
/// The octopus — one mind, many arms — and the "nex" wordmark are kept here as
/// the path data of `docs/nex_logo.svg` and `docs/nex_logo_type.svg`, so they
/// stay sharp at any size and can be taken apart for the splash animation.
/// Pictures of them (launcher icons, the Android splash, the notification
/// icon) are built from the same files by `tools/generate_brand_assets.py`.
abstract final class NexBrand {
  /// The brand blue of the mark and wordmark.
  static const blue = Color(0xFF0084F7);

  /// The ink everything else is drawn in, per brightness.
  static Color ink(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFF4F5F5)
      : const Color(0xFF1D1D1D);

  /// The head and both outer arms.
  static final ui.Path body = nexSvgPath(_body);

  /// The left inner arm, in ink.
  static final ui.Path leftArm = nexSvgPath(_leftArm);

  /// The right inner arm, in blue.
  static final ui.Path blueArm = nexSvgPath(_blueArm);

  /// The blue eye, on the left.
  static const blueEye = Offset(105.9301, 127.6255);

  /// The ink eye, on the right.
  static const inkEye = Offset(131.9448, 127.6255);

  static const eyeRadius = 10.3497;

  /// Where the mark's ink sits in its own coordinates.
  static final Rect markBounds = body
      .getBounds()
      .expandToInclude(leftArm.getBounds())
      .expandToInclude(blueArm.getBounds());

  /// The wordmark's n, e and the ink strokes of the x.
  static final ui.Path wordN = nexSvgPath(_n);
  static final ui.Path wordE = nexSvgPath(_e)
    ..fillType = ui.PathFillType.evenOdd;
  static final ui.Path wordX = nexSvgPath(_xLow)
    ..addPath(nexSvgPath(_xHigh), Offset.zero);

  /// The x's blue stroke.
  static final ui.Path swoosh = nexSvgPath(_swoosh);

  /// The blue dot after the x.
  static const dot = Offset(823.2855, 111.6896);
  static const dotRadius = 22.7299;

  /// Where the wordmark's ink sits in its own coordinates.
  static final Rect wordBounds = wordN
      .getBounds()
      .expandToInclude(wordE.getBounds())
      .expandToInclude(wordX.getBounds())
      .expandToInclude(swoosh.getBounds())
      .expandToInclude(Rect.fromCircle(center: dot, radius: dotRadius));

  /// The left inner arm.
  static const _leftArm =
      'M108.6274,172.054c-2.9109-.0014-5.4976,2.2664-5.519,5.4205l-.1368,20.1978-.1173,25.3949c-.0482,10.4166-10.7,18.5768-20.7668,18.5532l-28.5762-.0668c-10.3431-.4128-20.1362-10.3821-20.183-20.4744l-.0492-10.601c0-.0037.0002-.0073.0002-.011.403-7.9166,5.2051-14.6503,12.0643-18.3325,3.597-1.931,7.2662-2.8043,11.3593-2.7962l8.2596.0164,9.056.0322c2.7626.0098,5.0063-2.2293,5.0021-4.992-.0042-2.7495-2.234-4.9763-4.9835-4.9768l-18.5241-.0034c-5.485.2311-10.5704,1.4846-15.3559,4.1522-6.4368,3.5881-11.6586,8.9697-14.9488,15.5867-3.401,6.8397-3.7127,15.5106-3.0237,23.0826.402,4.4173,1.7016,8.7273,3.9644,12.5422,3.5679,6.0152,8.694,10.8138,14.9407,13.8792,4.2614,2.0911,8.6578,3.0325,13.422,3.026l27.9886-.038c6.784-.0092,13.1212-2.0891,18.601-5.9681,2.7289-1.9318,5.0879-4.0449,7.101-6.7124,3.7136-4.921,5.9424-10.6293,5.9483-16.9135l.0416-44.4263c.0031-3.2724-2.5424-5.5701-5.5646-5.5715Z';

  /// The head and both outer arms, one contour.
  static const _body =
      'M164.9855,55.278c10.3053,12.3194,15.2648,28.3142,13.4786,44.3103-.9949,8.9104-4.9261,17.3772-9.8051,24.8089l-5.7944,8.8261-6.7977,10.4227c-4.022,6.1669-7.8889,12.252-11.4667,18.681l-3.0257,6.1617c-2.3876,4.8624-2.8956,9.9833-2.8782,15.3888l.1199,37.317c.0228,7.0851,6.7451,12.9695,13.7455,12.9726l29.2828.0129c2.9592.0013,5.6697-1.1006,7.9923-2.7471,3.5342-2.5053,5.8526-6.3134,6.09-10.6855.1696-3.1231.2308-6.1141-.0728-9.2849-.7532-7.8677-7.451-13.9319-15.3707-13.9448l-10.6483-.0173c-6.9958-.0114-12.675,5.653-12.6821,12.6487-.0025,2.4847,2.0095,4.5012,4.4942,4.5043l1.7687.0023c2.4738.0031,4.4861-1.9914,4.5052-4.4651.0115-1.4948,1.2312-2.6979,2.726-2.689l9.5457.0566c2.9779.0176,5.1542,2.6768,5.1259,5.4799l-.0653,6.4632c-.026,2.5661-2.5486,4.7206-5.1884,4.7247l-24.9561.0389c-2.8465.0044-5.3843-2.4256-5.3867-5.2321l-.0317-37.36c-.0029-3.4337.9073-6.6132,2.3858-9.5922l1.6119-3.248c3.5032-6.2958,7.3059-12.2708,11.2437-18.3436l15.2606-23.5348c3.877-5.9791,6.6165-12.4188,8.2414-19.3401,3.9214-16.7032-.2288-36.2953-9.5403-50.6548-5.3591-8.2641-12.2083-15.4023-20.1663-21.1974-5.0789-3.6984-10.4885-6.512-16.3832-8.6584-7.8343-2.8527-15.8136-4.2911-23.7484-4.35h-1c-7.9348.0588-15.9141,1.4973-23.7484,4.35-5.8947,2.1464-11.3043,4.96-16.3832,8.6584-7.9581,5.795-14.8073,12.9333-20.1663,21.1974-9.3116,14.3594-13.4617,33.9515-9.5403,50.6548,1.6249,6.9213,4.3644,13.361,8.2414,19.3401l15.2606,23.5348c3.9378,6.0729,7.7405,12.0479,11.2437,18.3436l1.6119,3.248c1.4785,2.9789,2.3887,6.1584,2.3858,9.5922l-.0317,37.36c-.0024,2.8065-2.5402,5.2365-5.3867,5.2321l-24.9561-.0389c-2.6398-.0041-5.1624-2.1586-5.1884-4.7247l-.0653-6.4632c-.0284-2.8031,2.1479-5.4622,5.1259-5.4799l9.5457-.0566c1.4948-.0089,2.7144,1.1943,2.726,2.689.019,2.4738,2.0314,4.4682,4.5052,4.4651l1.7687-.0023c2.4847-.0031,4.4967-2.0195,4.4942-4.5043-.0071-6.9958-5.6863-12.6601-12.6821-12.6487l-10.6483.0173c-7.9197.0128-14.6176,6.077-15.3707,13.9448-.3036,3.1708-.2423,6.1618-.0728,9.2849.2374,4.3721,2.5558,8.1802,6.09,10.6855,2.3226,1.6464,5.0331,2.7484,7.9923,2.7471l29.2828-.0129c7.0005-.0031,13.7227-5.8875,13.7455-12.9726l.1199-37.317c.0174-5.4055-.4906-10.5264-2.8782-15.3888l-3.0257-6.1617c-3.5778-6.4291-7.4446-12.5142-11.4667-18.681l-6.7977-10.4227-5.7944-8.8261c-4.879-7.4317-8.8102-15.8985-9.8051-24.8089-1.7862-15.9961,3.1733-31.9909,13.4786-44.3103,6.0887-7.2787,13.7703-13.0823,22.3987-17.0183,7.7969-3.5567,15.9079-5.3321,23.991-5.4078h1c8.0831.0757,16.1942,1.8511,23.991,5.4078,8.6284,3.936,16.3101,9.7396,22.3987,17.0183Z';

  /// The right inner arm, in blue.
  static const _blueArm =
      'M210.9834,199.1538c-3.2903-6.6169-8.512-11.9985-14.9489-15.5867-4.7854-2.6676-9.8708-3.9211-15.3559-4.1522l-18.524.0034c-2.7495.0005-4.9794,2.2273-4.9836,4.9768-.0042,2.7627,2.2394,5.0018,5.0021,4.992l9.0559-.0322,8.2596-.0164c4.0931-.0081,7.7623.8652,11.3593,2.7962,6.8591,3.6822,11.6613,10.416,12.0643,18.3325.0001.0037.0002.0073.0003.011l-.0492,10.601c-.0468,10.0923-9.84,20.0616-20.183,20.4744l-28.5763.0668c-10.0669.0236-20.7187-8.1366-20.7668-18.5532l-.1174-25.3949-.1368-20.1978c-.0214-3.1541-2.6082-5.4219-5.519-5.4205-3.0222.0015-5.5676,2.2991-5.5646,5.5715l.0416,44.4263c.0059,6.2842,2.2346,11.9926,5.9482,16.9135,2.0131,2.6675,4.372,4.7806,7.101,6.7124,5.4799,3.879,11.817,5.9589,18.601,5.9681l27.9885.038c4.7642.0065,9.1607-.9349,13.422-3.026,6.2466-3.0653,11.3729-7.864,14.9407-13.8792,2.2628-3.8149,3.5625-8.1249,3.9644-12.5422.689-7.572.3773-16.2429-3.0236-23.0826Z';

  /// The wordmark's n.
  static const _n =
      'M273.2514,198.0063c-27.9847,0-50.6708-22.6861-50.6708-50.6708v-52.0313c0-30.6064-8.5015-38.0879-41.1484-38.0879h-55.0918c-31.9668,0-41.1489,7.4814-41.1489,38.0879v102.7021h-50.6709v-104.4023c0-58.8325,20.0645-79.917,88.4189-79.917h61.5532c68.6948,0,88.7588,21.0845,88.7588,79.917v104.4023h0Z';

  /// The e, with its counter as a second subpath (even-odd).
  static const _e =
      'M361.3315,124.5507v8.5015c0,22.4448,6.8018,26.5259,30.6064,26.5259h59.853c0,21.2233-17.2049,38.4282-38.4282,38.4282h-21.4248c-58.4922,0-81.2773-21.0845-81.2773-70.0552v-42.5088c0-53.7314,18.7041-71.7554,83.6582-71.7554h89.0986c52.7114,0,67.3345,21.0845,67.3345,50.3306v60.5332h-189.4204ZM500.081,68.0985c0-12.2427-5.4409-15.3032-20.7441-15.3032h-84.3379c-25.5059,0-33.6675,2.7207-33.6675,29.2461v9.8623h138.7495v-23.8052Z';

  /// The blue stroke of the x.
  static const _swoosh =
      'M608.5122,198.0063s-62.7047-.6252-62.7047,0C706.3112,3.3623,890.5281,15.9327,890.5281,15.9327c0,0-143.038,7.1349-282.0159,182.0736Z';

  /// The lower half of the x's other stroke.
  static const _xLow =
      'M682.8498,139.6855l11.2852,12.0868c55.9391,55.9391,66.0732,46.2338,106.4205,46.234h0s-85.3818-86.3167-85.3818-86.3167c-10.6105,8.4734-21.4095,17.7771-32.3239,27.9958Z';

  /// The upper half of the x's other stroke.
  static const _xHigh =
      'M666.0425,64.4799l-48.7862-50.7931h-60.873s75.4403,74.8124,75.4403,74.8124c11.3323-8.8257,22.7773-16.8059,34.2189-24.0193Z';
}

/// Parses SVG path data into a [ui.Path].
///
/// Covers what the brand files use and their neighbours — M, L, H, V, C, S and
/// Z, absolute and relative — and throws on anything else rather than drawing
/// something subtly wrong.
ui.Path nexSvgPath(String data) {
  final path = ui.Path();
  final tokens = RegExp(
    r'[A-DF-Za-df-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(data).map((m) => m[0]!).toList();
  var i = 0;
  var command = '';
  var x = 0.0, y = 0.0;
  var startX = 0.0, startY = 0.0;
  // The second control point of the last curve, for S's reflection.
  double? controlX, controlY;

  bool isCommand(String token) => RegExp(r'^[A-Za-z]$').hasMatch(token);
  double next() {
    if (i >= tokens.length || isCommand(tokens[i])) {
      throw FormatException('command $command is missing a number', data);
    }
    return double.parse(tokens[i++]);
  }

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      command = tokens[i++];
    } else if (command.isEmpty) {
      throw FormatException('path data must start with a command', data);
    }
    final relative = command == command.toLowerCase();
    final ox = relative ? x : 0.0, oy = relative ? y : 0.0;
    switch (command.toUpperCase()) {
      case 'M':
        x = ox + next();
        y = oy + next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        controlX = controlY = null;
        // Further pairs after a move are lines.
        command = relative ? 'l' : 'L';
      case 'L':
        x = ox + next();
        y = oy + next();
        path.lineTo(x, y);
        controlX = controlY = null;
      case 'H':
        x = ox + next();
        path.lineTo(x, y);
        controlX = controlY = null;
      case 'V':
        y = oy + next();
        path.lineTo(x, y);
        controlX = controlY = null;
      case 'C':
        final x1 = ox + next(), y1 = oy + next();
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        controlX = x2;
        controlY = y2;
      case 'S':
        final x1 = controlX == null ? x : 2 * x - controlX;
        final y1 = controlY == null ? y : 2 * y - controlY;
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        controlX = x2;
        controlY = y2;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        controlX = controlY = null;
      default:
        throw FormatException('unsupported path command $command', data);
    }
  }
  return path;
}

/// The octopus on its own, fitted into a box of [size], in the theme's ink.
class NexMark extends StatelessWidget {
  const NexMark({super.key, required this.size, this.semanticLabel = 'Nex'});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(NexBrand.ink(Theme.of(context).brightness)),
    );
    return semanticLabel == null
        ? mark
        : Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = NexBrand.markBounds;
    final scale = (size.width / bounds.width) < (size.height / bounds.height)
        ? size.width / bounds.width
        : size.height / bounds.height;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-bounds.center.dx, -bounds.center.dy);
    nexPaintMark(canvas, ink: ink);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink;
}

/// Paints the whole mark in its own coordinates.
void nexPaintMark(
  Canvas canvas, {
  required Color ink,
  Color blue = NexBrand.blue,
}) {
  final inkPaint = Paint()..color = ink;
  final bluePaint = Paint()..color = blue;
  canvas
    ..drawPath(NexBrand.body, inkPaint)
    ..drawPath(NexBrand.leftArm, inkPaint)
    ..drawPath(NexBrand.blueArm, bluePaint)
    ..drawCircle(NexBrand.blueEye, NexBrand.eyeRadius, bluePaint)
    ..drawCircle(NexBrand.inkEye, NexBrand.eyeRadius, inkPaint);
}

/// The "nex" wordmark, [height] tall, in the theme's ink and the brand blue.
class NexLogotype extends StatelessWidget {
  const NexLogotype({
    super.key,
    required this.height,
    this.semanticLabel = 'Nex',
  });

  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bounds = NexBrand.wordBounds;
    final logotype = CustomPaint(
      size: Size(height * bounds.width / bounds.height, height),
      painter: _LogotypePainter(NexBrand.ink(Theme.of(context).brightness)),
    );
    return semanticLabel == null
        ? logotype
        : Semantics(label: semanticLabel, image: true, child: logotype);
  }
}

class _LogotypePainter extends CustomPainter {
  _LogotypePainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = NexBrand.wordBounds;
    final scale = size.height / bounds.height;
    canvas
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    final inkPaint = Paint()..color = ink;
    final bluePaint = Paint()..color = NexBrand.blue;
    canvas
      ..drawPath(NexBrand.wordN, inkPaint)
      ..drawPath(NexBrand.wordE, inkPaint)
      ..drawPath(NexBrand.wordX, inkPaint)
      ..drawPath(NexBrand.swoosh, bluePaint)
      ..drawCircle(NexBrand.dot, NexBrand.dotRadius, bluePaint);
  }

  @override
  bool shouldRepaint(_LogotypePainter old) => old.ink != ink;
}
