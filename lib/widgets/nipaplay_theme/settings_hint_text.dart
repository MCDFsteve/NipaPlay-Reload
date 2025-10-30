import 'package:flutter/material.dart';
import 'theme_color_utils.dart';

class SettingsHintText extends StatelessWidget {
  final String text;
  const SettingsHintText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: ThemeColorUtils.secondaryForeground(context),
        fontSize: 12,
      ),
      textAlign: TextAlign.left,
    );
  }
}
