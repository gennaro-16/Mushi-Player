import 'package:flutter/material.dart';

class SongMetaRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final TextStyle textStyle;
  final double iconSize;
  final double spacing;

  const SongMetaRow({
    super.key,
    required this.icon,
    required this.value,
    required this.textStyle,
    this.iconSize = 16,
    this.spacing = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: iconSize),
        SizedBox(width: spacing),
        Text(value, style: textStyle),
      ],
    );
  }
}
