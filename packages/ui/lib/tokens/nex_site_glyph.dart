import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

/// A local site mark for recognised domains. Unknown hosts can use a favicon.
class NexSiteGlyph extends StatelessWidget {
  const NexSiteGlyph({super.key, required this.face, required this.size});
  final NexLinkFace face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = Color(face.brandColor ?? 0xff526476);
    final mark = switch (face.name) {
      'Aparat' => Icons.play_arrow_rounded,
      'Instagram' => Icons.camera_alt_outlined,
      'Telegram' => Icons.send_rounded,
      'GitHub' => Icons.fork_right_rounded,
      'Digikala' => Icons.shopping_bag_outlined,
      'Divar' => Icons.storefront_rounded,
      'Snapp' => Icons.local_taxi_rounded,
      'Balad' => Icons.directions_rounded,
      'Neshan' => Icons.place_rounded,
      'Spotify' => Icons.graphic_eq_rounded,
      'Reddit' => Icons.smart_toy_outlined,
      'Stack Overflow' => Icons.layers_outlined,
      'Zoomit' => Icons.bolt_rounded,
      'Netlify' => Icons.auto_awesome_rounded,
      'Google' when face.kind == NexLinkKind.place => Icons.location_on_rounded,
      _ => null,
    };
    final label = switch (face.name) {
      'LinkedIn' => 'in',
      'Virgool' => '،',
      _ => face.name.characters.firstOrNull ?? '#',
    };
    final ink = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Container(
            width: size,
            height: face.name == 'YouTube' ? size * 0.72 : size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(size * 0.25),
            ),
            child: face.name == 'YouTube'
                ? CustomPaint(
                    size: Size.square(size * 0.46),
                    painter: const _YouTubePlay(),
                  )
                : mark != null
                ? Icon(mark, size: size * 0.72, color: ink)
                : Text(
                    label,
                    textDirection: TextDirection.ltr,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      inherit: false,
                      fontWeight: FontWeight.w800,
                      fontSize: size * 0.59,
                      height: 1,
                      color: ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Keep the video brand distinct from the actual play control on the card.
class _YouTubePlay extends CustomPainter {
  const _YouTubePlay();

  @override
  void paint(Canvas canvas, Size size) {
    final play = Path()
      ..moveTo(size.width * 0.27, size.height * 0.12)
      ..lineTo(size.width * 0.89, size.height * 0.5)
      ..lineTo(size.width * 0.27, size.height * 0.88)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_YouTubePlay oldDelegate) => false;
}
