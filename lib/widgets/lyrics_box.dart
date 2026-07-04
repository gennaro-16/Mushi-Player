import 'package:flutter/material.dart';

class LyricsBox extends StatelessWidget {
  final String lyrics;
  final EdgeInsetsGeometry padding;
  final TextStyle textStyle;
  final double backgroundOpacity;
  final BorderRadiusGeometry borderRadius;

  const LyricsBox({
    super.key,
    required this.lyrics,
    required this.textStyle,
    this.padding = const EdgeInsets.all(16),
    this.backgroundOpacity = 0.08,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: backgroundOpacity),
        borderRadius: borderRadius,
      ),
      child: Text(lyrics, style: textStyle),
    );
  }
}
