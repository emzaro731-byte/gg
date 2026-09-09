import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GGBrandMark extends StatelessWidget {
  const GGBrandMark({super.key, this.size = 72, this.showGlow = true});
  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(size * .22),
      child: SvgPicture.asset(
        'assets/branding/gg_logo.svg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
    if (!showGlow) return mark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B5CFF).withValues(alpha: .28),
            blurRadius: size * .28,
            spreadRadius: size * .04,
          ),
        ],
      ),
      child: mark,
    );
  }
}
