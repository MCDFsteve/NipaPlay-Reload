library fluent_ui_stub;

import 'package:flutter/material.dart' as material
  show Card, ListTile, Tab, TabBar, TabBarView, TabController, Checkbox, Radio;
import 'package:flutter/material.dart' hide Card, ListTile, Tab;
import 'package:flutter/services.dart' show TextInputFormatter;

export 'package:flutter/material.dart' hide Card, ListTile, Tab;

extension FluentColorWithValues on Color {
  Color withValues({double? alpha, double? opacity}) {
    final double resolved = (alpha ?? opacity ?? (this.alpha / 255)).clamp(0.0, 1.0);
    return withAlpha((resolved * 255).round());
  }
}

extension FluentMaterialColorWithValues on MaterialColor {
  Color withValues({double? alpha, double? opacity}) {
    return Color(value).withValues(alpha: alpha, opacity: opacity);
  }
}

extension FluentMaterialAccentColorWithValues on MaterialAccentColor {
  Color withValues({double? alpha, double? opacity}) {
    return Color(value).withValues(alpha: alpha, opacity: opacity);
  }
}

typedef InfoBarBuilder = Widget Function(BuildContext context, VoidCallback close);

enum InfoBarSeverity { info, success, warning, error }

void displayInfoBar(
  BuildContext context, {
  required InfoBarBuilder builder,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: duration,
      behavior: SnackBarBehavior.floating,
      content: builder(context, () => messenger.hideCurrentSnackBar()),
    ),
  );
}

class FluentTheme {
  const FluentTheme._();

  static FluentThemeData of(BuildContext context) => FluentThemeData._(context);
}

class FluentThemeData {
  FluentThemeData._(this._context);

  final BuildContext _context;

  ThemeData get _theme => Theme.of(_context);

  Color get accentColor => _theme.colorScheme.primary;

  Color get inactiveColor => _theme.disabledColor;

  Color get cardColor => _theme.cardColor;

  Color get acrylicBackgroundColor => _theme.colorScheme.surface.withOpacity(0.9);

  Color get shadowColor => _theme.shadowColor;

  Color get micaBackgroundColor => _theme.colorScheme.surfaceVariant;

  Brightness get brightness => _theme.brightness;

  FluentTypography get typography => FluentTypography(_context);

  FluentResources get resources => FluentResources(_context);

  NavigationPaneThemeData get navigationPaneTheme => NavigationPaneThemeData(_theme);

  Color get scaffoldBackgroundColor => _theme.colorScheme.surface;
}

class FluentTypography {
  FluentTypography(this._context);

  final BuildContext _context;

  TextTheme get _textTheme => Theme.of(_context).textTheme;

  TextStyle? get body => _textTheme.bodyMedium ?? _textTheme.bodyLarge;

  TextStyle? get bodyLarge => _textTheme.bodyLarge ?? _textTheme.headlineSmall;

  TextStyle? get bodyStrong =>
      (_textTheme.bodyMedium ?? _textTheme.bodyLarge)?.copyWith(fontWeight: FontWeight.w600);

  TextStyle? get caption => _textTheme.bodySmall ?? _textTheme.labelSmall;

  TextStyle? get subtitle => _textTheme.titleMedium ?? _textTheme.titleLarge;

  TextStyle? get title =>
    _textTheme.titleMedium ?? _textTheme.headlineSmall ?? _textTheme.titleLarge;

  TextStyle? get titleLarge =>
    _textTheme.titleLarge ?? _textTheme.headlineSmall ?? _textTheme.headlineMedium;
}

class FluentResources {
  FluentResources(this._context);

  final BuildContext _context;

  ThemeData get _theme => Theme.of(_context);

  ColorScheme get _scheme => _theme.colorScheme;

  Color get textFillColorPrimary => _scheme.onSurface;

  Color get textFillColorSecondary => _scheme.onSurface.withOpacity(0.7);

  Color get textFillColorTertiary => _scheme.onSurface.withOpacity(0.5);

  Color get textFillColorDisabled => _scheme.onSurface.withOpacity(0.3);

  Color get controlFillColorDefault => _scheme.surfaceVariant.withOpacity(0.5);

  Color get controlFillColorSecondary => _scheme.surfaceVariant.withOpacity(0.3);

  Color get controlStrokeColorDefault => _theme.dividerColor;

  Color get controlStrokeColorSecondary => _theme.dividerColor.withOpacity(0.6);

  Color get subtleFillColorSecondary => _scheme.surfaceVariant.withOpacity(0.4);

  Color get solidBackgroundFillColorSecondary => _scheme.surfaceVariant;

  Color get systemFillColorCritical => _scheme.error;

  Color get dividerStrokeColorDefault => _theme.dividerColor;
}

class NavigationPaneThemeData {
  NavigationPaneThemeData(this._theme);

  final ThemeData _theme;

  Color get backgroundColor => _theme.colorScheme.surfaceVariant.withOpacity(0.2);
}

class InfoBar extends StatelessWidget {
  const InfoBar({
    super.key,
    this.title,
    this.content,
    this.action,
    this.severity = InfoBarSeverity.info,
    this.isLong = false,
    this.onClose,
  });

  final Widget? title;
  final Widget? content;
  final Widget? action;
  final InfoBarSeverity severity;
  final bool isLong;
  final VoidCallback? onClose;

  Color _severityColor(ColorScheme scheme) {
    switch (severity) {
      case InfoBarSeverity.success:
        return scheme.secondary;
      case InfoBarSeverity.warning:
        return Colors.orange;
      case InfoBarSeverity.error:
        return scheme.error;
      case InfoBarSeverity.info:
        return scheme.primary;
    }
  }

  IconData _severityIcon() {
    switch (severity) {
      case InfoBarSeverity.success:
        return FluentIcons.check_mark;
      case InfoBarSeverity.warning:
        return FluentIcons.warning;
      case InfoBarSeverity.error:
        return FluentIcons.error;
      case InfoBarSeverity.info:
        return FluentIcons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _severityColor(scheme);
    final background = color.withOpacity(0.08);

    return Container(
      width: isLong ? double.infinity : null,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: color.withOpacity(0.4), width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_severityIcon(), color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  DefaultTextStyle.merge(
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    child: title!,
                  ),
                if (content != null) ...[
                  if (title != null) const SizedBox(height: 4),
                  DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodySmall,
                    child: content!,
                  ),
                ],
              ],
            ),
          ),
          if (action != null || onClose != null) ...[
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (action != null) action!,
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: color,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: '关闭',
                    onPressed: onClose,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class InfoBadge extends StatelessWidget {
  const InfoBadge({
    super.key,
    this.source,
    this.icon,
    this.color,
    this.padding,
  });

  final Widget? source;
  final Widget? icon;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final Color accent = color ?? Theme.of(context).colorScheme.primary;
    final Widget content = source ?? icon ?? const SizedBox.shrink();

  return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.6), width: 1),
      ),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: accent),
        child: IconTheme.merge(
          data: IconThemeData(color: accent, size: 14),
          child: content,
        ),
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    this.strokeWidth = 3.0,
    this.size = 24.0,
    this.value,
    this.color,
  });

  final double strokeWidth;
  final double size;
  final double? value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        value: value,
        valueColor: color != null ? AlwaysStoppedAnimation<Color>(color!) : null,
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    this.value,
    this.backgroundColor,
    this.activeColor,
  });

  final double? value;
  final Color? backgroundColor;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final double? progress = value == null ? null : (value!.clamp(0, 100) / 100);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: backgroundColor,
        valueColor: activeColor != null ? AlwaysStoppedAnimation<Color>(activeColor!) : null,
      ),
    );
  }
}

class Button extends StatelessWidget {
  const Button({super.key, required this.child, this.onPressed, this.style});

  final Widget child;
  final VoidCallback? onPressed;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class FilledButton extends StatelessWidget {
  const FilledButton({super.key, required this.child, this.onPressed, this.style});

  final Widget child;
  final VoidCallback? onPressed;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class HyperlinkButton extends StatelessWidget {
  const HyperlinkButton({super.key, required this.child, this.onPressed, this.padding});

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: padding ?? EdgeInsets.zero,
        foregroundColor: accent,
        textStyle: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(decoration: TextDecoration.underline) ??
            const TextStyle(decoration: TextDecoration.underline),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.underline),
        child: child,
      ),
    );
  }
}

enum WidgetState { hovered, pressed, focused, disabled }

extension WidgetStateSetX on Set<WidgetState> {
  bool get isHovered => contains(WidgetState.hovered);
  bool get isPressed => contains(WidgetState.pressed);
  bool get isFocused => contains(WidgetState.focused);
  bool get isDisabled => contains(WidgetState.disabled);
}

class ButtonState<T> extends MaterialStateProperty<T> {
  ButtonState._(this._resolver);

  final T Function(Set<WidgetState>) _resolver;

  static ButtonState<T> all<T>(T value) {
    return ButtonState<T>._((_) => value);
  }

  static ButtonState<T> resolveWith<T>(T Function(Set<WidgetState>) resolver) {
    return ButtonState<T>._(resolver);
  }

  @override
  T resolve(Set<MaterialState> states) {
    final widgetStates = <WidgetState>{};
    if (states.contains(MaterialState.disabled)) {
      widgetStates.add(WidgetState.disabled);
    }
    if (states.contains(MaterialState.pressed)) {
      widgetStates.add(WidgetState.pressed);
    }
    if (states.contains(MaterialState.hovered)) {
      widgetStates.add(WidgetState.hovered);
    }
    if (states.contains(MaterialState.focused)) {
      widgetStates.add(WidgetState.focused);
    }
    return _resolver(widgetStates);
  }
}

class HoverButton extends StatefulWidget {
  const HoverButton({super.key, required this.builder, this.onPressed});

  final Widget Function(BuildContext, HoverButtonStates) builder;
  final VoidCallback? onPressed;

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final states = HoverButtonStates(
      isHovered: _hovered,
      isFocused: _focused,
      isPressed: _pressed,
      isDisabled: widget.onPressed == null,
    );

    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onPressed == null
              ? null
              : (_) => setState(() => _pressed = true),
          onTapUp: widget.onPressed == null
              ? null
              : (_) => setState(() => _pressed = false),
          onTapCancel: widget.onPressed == null
              ? null
              : () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: widget.builder(context, states),
        ),
      ),
    );
  }
}

class HoverButtonStates {
  const HoverButtonStates({
    required this.isHovered,
    required this.isFocused,
    required this.isPressed,
    required this.isDisabled,
  });

  final bool isHovered;
  final bool isFocused;
  final bool isPressed;
  final bool isDisabled;
}

class NavigationAppBar {
  const NavigationAppBar({
    this.title,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final Widget? leading;
  final Widget? actions;
  final bool automaticallyImplyLeading;

  PreferredSizeWidget buildAppBar(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: actions != null ? <Widget>[actions!] : null,
    );
  }
}

class NavigationView extends StatelessWidget {
  const NavigationView({super.key, this.appBar, required this.pane});

  final NavigationAppBar? appBar;
  final NavigationPane pane;

  @override
  Widget build(BuildContext context) {
    final body = pane.buildBody(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: appBar?.buildAppBar(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.3),
              border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: pane,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class NavigationPane extends StatelessWidget {
  const NavigationPane({
    super.key,
    required this.items,
    this.selected = 0,
    this.onChanged,
  });

  final List<PaneItem> items;
  final int selected;
  final ValueChanged<int>? onChanged;

  int get _currentIndex {
    if (items.isEmpty) {
      return 0;
    }
    if (selected < 0) {
      return 0;
    }
    if (selected >= items.length) {
      return items.length - 1;
    }
    return selected;
  }

  Widget buildBody(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return items[_currentIndex].body;
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary.withOpacity(0.1);
    final selectedTextColor = Theme.of(context).colorScheme.primary;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = index == _currentIndex;
        return ListTile(
          leading: IconTheme(
            data: IconThemeData(color: isSelected ? selectedTextColor : null),
            child: item.icon,
          ),
          title: DefaultTextStyle.merge(
            style: TextStyle(
              color: isSelected ? selectedTextColor : null,
              fontWeight: isSelected ? FontWeight.w600 : null,
            ),
            child: item.title ?? const SizedBox.shrink(),
          ),
          selected: isSelected,
          selectedTileColor: selectedColor,
          onTap: onChanged == null ? null : () => onChanged!(index),
        );
      },
    );
  }
}

class PaneItem {
  const PaneItem({required this.icon, this.title, required this.body});

  final Widget icon;
  final Widget? title;
  final Widget body;
}

enum TabWidthBehavior { equal, sizeToContent }

enum CloseButtonVisibilityMode { never, always, onHover }

class Tab {
  const Tab({this.text, this.icon, this.header, required this.body});

  final Widget? text;
  final Widget? icon;
  final Widget? header;
  final Widget body;
}

class TabView extends StatefulWidget {
  const TabView({
    super.key,
    required this.tabs,
    this.currentIndex = 0,
    this.onChanged,
    this.tabWidthBehavior = TabWidthBehavior.equal,
    this.closeButtonVisibility = CloseButtonVisibilityMode.never,
  });

  final List<Tab> tabs;
  final int currentIndex;
  final ValueChanged<int>? onChanged;
  final TabWidthBehavior tabWidthBehavior;
  final CloseButtonVisibilityMode closeButtonVisibility;

  @override
  State<TabView> createState() => _TabViewState();
}

class _TabViewState extends State<TabView> with SingleTickerProviderStateMixin {
  late material.TabController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    final int length = widget.tabs.isEmpty ? 1 : widget.tabs.length;
    final int initialIndex = widget.tabs.isEmpty
        ? 0
        : widget.currentIndex.clamp(0, length - 1);
    _controller = material.TabController(
      length: length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _controller.addListener(_handleIndexChanged);
  }

  void _handleIndexChanged() {
    if (_controller.indexIsChanging) {
      return;
    }
    if (widget.tabs.isEmpty) {
      return;
    }
    widget.onChanged?.call(_controller.index.clamp(0, widget.tabs.length - 1));
  }

  @override
  void didUpdateWidget(TabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabs.length != oldWidget.tabs.length) {
      _controller.removeListener(_handleIndexChanged);
      _controller.dispose();
      _createController();
    } else if (widget.tabs.isNotEmpty && widget.currentIndex != _controller.index) {
      final int index = widget.currentIndex.clamp(0, widget.tabs.length - 1);
      if (_controller.index != index) {
        _controller.index = index;
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleIndexChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final labels = widget.tabs
        .map(
          (tab) => material.Tab(
            icon: tab.icon,
            child: tab.text ?? tab.header ?? const SizedBox.shrink(),
          ),
        )
        .toList(growable: false);

    return Column(
      children: [
        material.TabBar(
          controller: _controller,
          isScrollable: widget.tabWidthBehavior == TabWidthBehavior.sizeToContent,
          tabs: labels,
        ),
        Expanded(
          child: material.TabBarView(
            controller: _controller,
            children: widget.tabs.map((tab) => tab.body).toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class ListTile extends StatelessWidget {
  const ListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.isThreeLine = false,
    this.dense,
    this.visualDensity,
    this.focusNode,
    this.autofocus = false,
    this.onPressed,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selected = false,
    this.tileColor,
    this.selectedTileColor,
    this.hoverColor,
    this.focusColor,
    this.contentPadding,
    this.shape,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.minLeadingWidth,
    this.mouseCursor,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool isThreeLine;
  final bool? dense;
  final VisualDensity? visualDensity;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onPressed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final bool selected;
  final Color? tileColor;
  final Color? selectedTileColor;
  final Color? hoverColor;
  final Color? focusColor;
  final EdgeInsetsGeometry? contentPadding;
  final ShapeBorder? shape;
  final double? horizontalTitleGap;
  final double? minVerticalPadding;
  final double? minLeadingWidth;
  final MouseCursor? mouseCursor;

  @override
  Widget build(BuildContext context) {
    return material.ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      isThreeLine: isThreeLine,
      dense: dense,
      visualDensity: visualDensity,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      onTap: onPressed ?? onTap,
      onLongPress: onLongPress,
      selected: selected,
      tileColor: tileColor,
      selectedTileColor: selectedTileColor,
      hoverColor: hoverColor,
      focusColor: focusColor,
      contentPadding: contentPadding,
      shape: shape,
      horizontalTitleGap: horizontalTitleGap,
      minVerticalPadding: minVerticalPadding,
      minLeadingWidth: minLeadingWidth,
      mouseCursor: mouseCursor,
    );
  }
}

class Card extends StatelessWidget {
  const Card({
    super.key,
    this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.color,
    this.borderRadius,
    this.border,
    this.elevation,
    this.shadowColor,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final BoxBorder? border;
  final double? elevation;
  final Color? shadowColor;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    Widget content = child ?? const SizedBox.shrink();
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    final BorderRadiusGeometry effectiveRadius = borderRadius ?? BorderRadius.circular(8);
    final Color effectiveColor = backgroundColor ?? color ?? Theme.of(context).cardColor;

    Widget card = material.Card(
      color: effectiveColor,
      elevation: elevation,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(borderRadius: effectiveRadius),
      clipBehavior: clipBehavior,
      child: border == null
          ? content
          : Container(
              decoration: BoxDecoration(
                border: border,
                borderRadius: effectiveRadius,
              ),
              child: content,
            ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }
}

class CommandBar extends StatelessWidget {
  const CommandBar({
    super.key,
    this.primaryItems = const <Widget>[],
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.spacing = 8.0,
  });

  final List<Widget> primaryItems;
  final MainAxisAlignment mainAxisAlignment;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: spacing,
      runSpacing: spacing,
      children: primaryItems,
    );
  }
}

class CommandBarButton extends StatelessWidget {
  const CommandBarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final Widget icon;
  final Widget label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: label,
    );
  }
}

class InfoLabel extends StatelessWidget {
  const InfoLabel({super.key, required this.label, required this.child, this.labelStyle});

  final String label;
  final Widget child;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final style = labelStyle ?? Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: style),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class ToggleSwitch extends StatelessWidget {
  const ToggleSwitch({
    super.key,
    required this.checked,
    this.onChanged,
    this.content,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final switchWidget = Switch(value: checked, onChanged: onChanged);
    if (content == null) {
      return switchWidget;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        switchWidget,
        const SizedBox(width: 8),
        content!,
      ],
    );
  }
}

class ToggleButton extends StatelessWidget {
  const ToggleButton({super.key, required this.checked, this.onChanged, required this.child});

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    final borderColor = checked ? primary : Theme.of(context).dividerColor;
    final backgroundColor = checked ? primary.withOpacity(0.12) : Colors.transparent;

    Widget content = DefaultTextStyle.merge(
      style: TextStyle(color: checked ? primary : onSurface),
      child: IconTheme(
        data: IconThemeData(color: checked ? primary : onSurface),
        child: child,
      ),
    );

    content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: content,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      child: content,
    );
  }
}

class ComboBoxItem<T> {
  const ComboBoxItem({required this.value, required this.child});

  final T value;
  final Widget child;
}

class ComboBox<T> extends StatelessWidget {
  const ComboBox({
    super.key,
    this.value,
    this.placeholder,
  this.items = const [],
    this.onChanged,
    this.isExpanded = true,
  });

  final T? value;
  final Widget? placeholder;
  final List<ComboBoxItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final dropdownItems = items
        .map((item) => DropdownMenuItem<T>(value: item.value, child: item.child))
        .toList(growable: false);
    final selected = items.any((item) => item.value == value) ? value : null;

    return DropdownButton<T>(
      value: selected,
      hint: placeholder,
      items: dropdownItems,
      onChanged: onChanged,
      isExpanded: isExpanded,
    );
  }
}

class Checkbox extends StatelessWidget {
  const Checkbox({
    super.key,
    required this.checked,
    this.onChanged,
    this.content,
  });

  final bool? checked;
  final ValueChanged<bool?>? onChanged;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final bool effectiveValue = checked ?? false;
    final material.Checkbox materialCheckbox = material.Checkbox(
      value: effectiveValue,
      onChanged: onChanged,
    );

    if (content == null) {
      return materialCheckbox;
    }

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!effectiveValue),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          materialCheckbox,
          const SizedBox(width: 8),
          Flexible(child: content!),
        ],
      ),
    );
  }
}

class RadioButton extends StatelessWidget {
  const RadioButton({
    super.key,
    required this.checked,
    this.onChanged,
    this.content,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final material.Radio<bool> radio = material.Radio<bool>(
      value: true,
      groupValue: checked,
      onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
    );

    if (content == null) {
      return radio;
    }

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          radio,
          const SizedBox(width: 8),
          Flexible(child: content!),
        ],
      ),
    );
  }
}

class TextBox extends StatelessWidget {
  const TextBox({
    super.key,
    this.controller,
    this.placeholder,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled,
    this.style,
    this.textAlign = TextAlign.start,
    this.textInputAction,
    this.focusNode,
    this.obscureText = false,
    this.inputFormatters,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final bool autofocus;
  final bool readOnly;
  final bool? enabled;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: placeholder,
        prefixIcon: prefix,
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      autofocus: autofocus,
      readOnly: readOnly,
      enabled: enabled,
      style: style,
      textAlign: textAlign,
      textInputAction: textInputAction,
      obscureText: obscureText,
      inputFormatters: inputFormatters,
    );
  }
}

class PasswordBox extends StatelessWidget {
  const PasswordBox({super.key, this.controller, this.placeholder, this.autofocus = false});

  final TextEditingController? controller;
  final String? placeholder;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: placeholder,
        border: const OutlineInputBorder(),
      ),
      obscureText: true,
      autofocus: autofocus,
    );
  }
}

class ContentDialog extends StatelessWidget {
  const ContentDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.constraints,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final Widget? dialogContent;
    if (constraints != null && content != null) {
      dialogContent = ConstrainedBox(
        constraints: constraints!,
        child: content!,
      );
    } else {
      dialogContent = content;
    }

    return AlertDialog(
      title: title,
      content: dialogContent,
      actions: actions,
      scrollable: true,
      insetPadding: const EdgeInsets.all(24),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      contentTextStyle: Theme.of(context).textTheme.bodyMedium,
      actionsAlignment: MainAxisAlignment.end,
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, this.title, this.commandBar});

  final Widget? title;
  final Widget? commandBar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (title != null)
            DefaultTextStyle.merge(
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              child: title!,
            ),
          const Spacer(),
          if (commandBar != null) commandBar!,
        ],
      ),
    );
  }
}

class ScaffoldPage extends StatelessWidget {
  const ScaffoldPage({
    super.key,
    this.header,
    this.content,
    this.padding,
    this.scrollController,
  }) : children = null;

  const ScaffoldPage.scrollable({
    super.key,
    this.header,
    required this.children,
    this.padding,
    this.scrollController,
  }) : content = null;

  final Widget? header;
  final Widget? content;
  final List<Widget>? children;
  final EdgeInsetsGeometry? padding;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (children != null) {
      body = ListView(
        controller: scrollController,
        padding: padding ?? const EdgeInsets.all(16),
        children: children!,
      );
    } else {
      body = Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: content ?? const SizedBox.shrink(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) header!,
        Expanded(
          child: body,
        ),
      ],
    );
  }
}

class Expander extends StatefulWidget {
  const Expander({
    super.key,
    required this.header,
    required this.content,
    this.onStateChanged,
    this.initiallyExpanded = false,
  });

  final Widget header;
  final Widget content;
  final ValueChanged<bool>? onStateChanged;
  final bool initiallyExpanded;

  @override
  State<Expander> createState() => _ExpanderState();
}

class _ExpanderState extends State<Expander> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) {
        setState(() => _expanded = expanded);
        widget.onStateChanged?.call(expanded);
      },
      title: widget.header,
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      children: [widget.content],
    );
  }
}

class FluentIcons {
  static const IconData add = Icons.add;
  static const IconData add_friend = Icons.person_add;
  static const IconData app_icon_default = Icons.apps;
  static const IconData back = Icons.arrow_back;
  static const IconData back_to_window = Icons.flip_to_front;
  static const IconData brightness = Icons.brightness_medium;
  static const IconData chat = Icons.chat;
  static const IconData check_mark = Icons.check;
  static const IconData checkbox_composite = Icons.crop_square;
  static const IconData chevron_left = Icons.chevron_left;
  static const IconData chevron_right = Icons.chevron_right;
  static const IconData chrome_close = Icons.close;
  static const IconData chrome_minimize = Icons.minimize;
  static const IconData chrome_restore = Icons.crop_square;
  static const IconData clear = Icons.clear;
  static const IconData clock = Icons.access_time;
  static const IconData closed_caption = Icons.closed_caption;
  static const IconData cloud = Icons.cloud;
  static const IconData cloud_add = Icons.cloud_upload;
  static const IconData cloud_download = Icons.cloud_download;
  static const IconData code = Icons.code;
  static const IconData color = Icons.palette;
  static const IconData comment = Icons.comment;
  static const IconData contact = Icons.person;
  static const IconData copy = Icons.copy;
  static const IconData delete = Icons.delete;
  static const IconData desktop_flow = Icons.desktop_windows;
  static const IconData developer_tools = Icons.developer_mode;
  static const IconData edit = Icons.edit;
  static const IconData error = Icons.error;
  static const IconData fast_forward = Icons.fast_forward;
  static const IconData favorite_star = Icons.star_outline;
  static const IconData favorite_star_fill = Icons.star;
  static const IconData filter = Icons.filter_list;
  static const IconData folder = Icons.folder;
  static const IconData folder_open = Icons.folder_open;
  static const IconData full_screen = Icons.fullscreen;
  static const IconData globe = Icons.public;
  static const IconData heart = Icons.favorite_border;
  static const IconData heart_fill = Icons.favorite;
  static const IconData history = Icons.history;
  static const IconData home = Icons.home;
  static const IconData info = Icons.info;
  static const IconData key_phrase_extraction = Icons.vpn_key;
  static const IconData library = Icons.video_library;
  static const IconData list = Icons.list;
  static const IconData more = Icons.more_horiz;
  static const IconData new_folder = Icons.create_new_folder;
  static const IconData next = Icons.skip_next;
  static const IconData open_file = Icons.file_open;
  static const IconData pause = Icons.pause;
  static const IconData photo2 = Icons.photo;
  static const IconData play = Icons.play_arrow;
  static const IconData play_solid = Icons.play_circle_fill;
  static const IconData playlist_music = Icons.queue_music;
  static const IconData plug_connected = Icons.power;
  static const IconData plug_disconnected = Icons.power_off;
  static const IconData previous = Icons.skip_previous;
  static const IconData radio_btn_off = Icons.radio_button_unchecked;
  static const IconData radio_btn_on = Icons.radio_button_checked;
  static const IconData refresh = Icons.refresh;
  static const IconData remote = Icons.settings_remote;
  static const IconData rewind = Icons.fast_rewind;
  static const IconData save = Icons.save;
  static const IconData search = Icons.search;
  static const IconData send = Icons.send;
  static const IconData server = Icons.storage;
  static const IconData settings = Icons.settings;
  static const IconData shield = Icons.shield;
  static const IconData sign_out = Icons.logout;
  static const IconData signin = Icons.login;
  static const IconData sort = Icons.sort;
  static const IconData sort_down = Icons.arrow_downward;
  static const IconData sort_up = Icons.arrow_upward;
  static const IconData status_error_full = Icons.error;
  static const IconData sync = Icons.sync;
  static const IconData tag = Icons.sell;
  static const IconData video = Icons.videocam;
  static const IconData volume2 = Icons.volume_down;
  static const IconData volume3 = Icons.volume_up;
  static const IconData warning = Icons.warning;
  static const IconData wifi = Icons.wifi;
}
