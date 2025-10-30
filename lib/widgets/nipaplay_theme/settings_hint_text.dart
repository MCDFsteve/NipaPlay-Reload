import 'package:flutter/material.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

class SettingsHintText extends StatelessWidget {
  final String text;
  const SettingsHintText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.nipaplayColors;
    return Text(
      text,
      style: TextStyle(
        color: colors.textSecondary.withOpacity(0.75),
        fontSize: 12,
      ),
      textAlign: TextAlign.left,
    );
  }
}
