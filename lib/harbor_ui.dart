part of 'main.dart';

class HarborColors {
  static const copper = Color(0xFFE5A16B);
  static const teal = Color(0xFF69BDB0);
  final bool dark;
  final String accentName;
  const HarborColors(this.dark, {this.accentName = 'Copper'});
  static HarborColors of(BuildContext context) => HarborColors(
    MacosTheme.of(context).brightness == Brightness.dark,
    accentName: context.watch<SSHStore?>()?.preferences.accent ?? 'Copper',
  );
  Color get background =>
      dark ? const Color(0xFF111B28) : const Color(0xFFF5F2ED);
  Color get sidebar => dark ? const Color(0xFF0D1520) : const Color(0xFFECE8E1);
  Color get surface => dark ? const Color(0xFF182535) : const Color(0xFFFFFDF9);
  Color get border => dark ? const Color(0xFF293747) : const Color(0xFFDDD7CD);
  Color get text => dark ? const Color(0xFFE8EDF2) : const Color(0xFF263446);
  Color get muted => dark ? const Color(0xFF94A4B5) : const Color(0xFF6D7884);
  Color get selectionTint => accent.withValues(alpha: dark ? 0.30 : 0.24);
  Color get dropTint => accent.withValues(alpha: dark ? 0.38 : 0.30);
  Color get accent {
    final palette =
        harborAccentPalette[accentName] ?? harborAccentPalette['Copper']!;
    return dark ? palette.dark : palette.light;
  }
}

const harborGroupPalette = <String, Color>{
  'Teal': HarborColors.teal,
  'Violet': Color(0xFFAA9BDC),
  'Amber': Color(0xFFE5A16B),
  'Blue': Color(0xFF7FAED5),
  'Rose': Color(0xFFD68EAA),
};

/// Resolves a group color. Favorites is always copper; a user-chosen palette
/// entry wins over the deterministic name hash, which is only a fallback so
/// every group still gets a stable color out of the box.
Color groupColor(String name, {Map<String, String> palette = const {}}) {
  if (name == 'Favorites') return HarborColors.copper;
  final chosen = palette[name];
  if (chosen != null && harborGroupPalette.containsKey(chosen)) {
    return harborGroupPalette[chosen]!;
  }
  final colors = harborGroupPalette.values.toList();
  final code = name.runes.fold<int>(0, (value, char) => value + char);
  return colors[code % colors.length];
}

const _harborMarkAsset = 'assets/brand/harbor-mark.png';

/// Transparent outer mark with a dark terminal inset for readable white glyphs.
class HarborMark extends StatelessWidget {
  final double size;
  const HarborMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      children: [
        Positioned(
          left: size * 0.335,
          top: size * 0.41,
          width: size * 0.33,
          height: size * 0.34,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF172A42),
              borderRadius: BorderRadius.circular(size * 0.12),
            ),
          ),
        ),
        Image.asset(
          _harborMarkAsset,
          width: size,
          height: size,
          filterQuality: FilterQuality.high,
        ),
      ],
    ),
  );
}

/// The full app icon: the mark on a rounded tile. Use it where a self-contained
/// icon with its own background is expected (about, empty states), in contrast
/// to the bare [HarborMark]. The tile follows the current light/dark theme.
class HarborAppIcon extends StatelessWidget {
  final double size;
  const HarborAppIcon({super.key, this.size = 64});
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.dark
              ? const [Color(0xFF172A42), Color(0xFF0A1420)]
              : const [Color(0xFF203A5C), Color(0xFF0D1B2C)],
        ),
        borderRadius: BorderRadius.circular(size * 0.225),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.03),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.02),
      child: HarborMark(size: size * 0.84),
    );
  }
}

/// Placeholder shown when no connection is selected: brand icon with its own
/// background plus a short hint.
class HarborEmptyState extends StatelessWidget {
  final String message;
  const HarborEmptyState({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HarborAppIcon(size: 84),
          const SizedBox(height: 18),
          Text(message, style: TextStyle(fontSize: 13, color: colors.muted)),
        ],
      ),
    );
  }
}

class HarborMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final stroke = Paint()
      ..color = HarborColors.copper
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final arch = Path()
      ..moveTo(19, 72)
      ..lineTo(19, 47)
      ..cubicTo(19, 6, 81, 6, 81, 47)
      ..lineTo(81, 72);
    canvas.drawPath(arch, stroke);
    canvas.drawLine(const Offset(19, 55), const Offset(81, 55), stroke);
    canvas.drawCircle(
      const Offset(19, 80),
      7,
      Paint()..color = HarborColors.teal,
    );
    canvas.drawCircle(
      const Offset(81, 80),
      7,
      Paint()..color = HarborColors.teal,
    );
    canvas.drawCircle(
      const Offset(50, 55),
      6,
      Paint()..color = const Color(0xFFF3E7D6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Duration harborMotion(BuildContext context, [int milliseconds = 220]) =>
    (context.read<SSHStore?>()?.preferences.reduceMotion ?? false) ||
        MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class HarborGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  const HarborGlass({
    super.key,
    required this.child,
    this.radius = 12,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surface.withValues(alpha: colors.dark ? 0.8 : 0.94),
                colors.surface.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: colors.dark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.8),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class HarborButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool busy;
  final bool fullWidth;
  final Color? color;
  const HarborButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.busy = false,
    this.fullWidth = false,
    this.color,
  });
  @override
  State<HarborButton> createState() => _HarborButtonState();
}

class _HarborButtonState extends State<HarborButton> {
  bool hovered = false;
  bool pressed = false;
  bool focused = false;
  void invokeButton() {
    if (!widget.busy && widget.onPressed != null) widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final enabled = widget.onPressed != null;
    final interactive = enabled && !widget.busy;
    final fill = widget.color ?? colors.accent;
    final accent = widget.secondary
        ? (widget.color ?? colors.text)
        : (fill.computeLuminance() > 0.35
              ? const Color(0xFF17212B)
              : Colors.white);
    final background = widget.secondary
        ? colors.text.withValues(
            alpha: enabled && pressed
                ? 0.12
                : enabled && hovered
                ? 0.09
                : 0.045,
          )
        : !enabled
        ? colors.surface
        : Color.lerp(
            fill,
            pressed ? Colors.black : Colors.white,
            pressed
                ? 0.10
                : hovered
                ? 0.08
                : 0,
          )!;
    return Semantics(
      button: true,
      enabled: interactive,
      value: widget.busy ? 'Busy' : null,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: widget.busy
            ? SystemMouseCursors.progress
            : enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) {
          if (hovered != value) setState(() => hovered = value);
        },
        onShowFocusHighlight: (value) => setState(() => focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              invokeButton();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: interactive ? (_) => setState(() => pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => pressed = false) : null,
          onTapCancel: () => setState(() => pressed = false),
          onTap: enabled ? invokeButton : null,
          child: AnimatedScale(
            scale: 1,
            duration: harborMotion(context, 100),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: harborMotion(context, 120),
              width: widget.fullWidth ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(9),
                // Paint focus outside the button without adding layout insets.
                boxShadow: [
                  BoxShadow(
                    color: focused ? colors.accent : Colors.transparent,
                    spreadRadius: 1.5,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: widget.fullWidth
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: 15,
                      color: enabled ? accent : colors.muted,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: enabled ? accent : colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HarborFavoriteButton extends StatelessWidget {
  final SSHHost host;
  final double size;
  const HarborFavoriteButton({super.key, required this.host, this.size = 16});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final favorite = store.isFavorite(host);
    final colors = HarborColors.of(context);
    return Semantics(
      label: favorite ? 'Unpin ${host.hostAlias}' : 'Pin ${host.hostAlias}',
      toggled: favorite,
      child: CupertinoButton(
        padding: const EdgeInsets.all(5),
        minimumSize: Size.zero,
        onPressed: () => store.toggleFavorite(host),
        child: Icon(
          favorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
          size: size,
          color: favorite ? colors.accent : colors.muted,
        ),
      ),
    );
  }
}

class HarborSearchReveal extends StatefulWidget {
  final bool visible;
  final Widget child;
  const HarborSearchReveal({
    super.key,
    required this.visible,
    required this.child,
  });
  @override
  State<HarborSearchReveal> createState() => _HarborSearchRevealState();
}

class _HarborSearchRevealState extends State<HarborSearchReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );
  @override
  void didUpdateWidget(HarborSearchReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      controller.animateTo(
        widget.visible ? 1 : 0,
        duration: harborMotion(context, 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (_, child) => Offstage(
      offstage: !widget.visible && controller.isDismissed,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: ExcludeFocus(
          excluding: !widget.visible,
          child: ClipRect(
            child: SizeTransition(
              sizeFactor: controller,
              axisAlignment: -1,
              child: FadeTransition(opacity: controller, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

class HarborPageTransition extends StatefulWidget {
  final Widget child;
  const HarborPageTransition({super.key, required this.child});
  @override
  State<HarborPageTransition> createState() => _HarborPageTransitionState();
}

class _HarborPageEntry {
  Widget child;
  double opacity;
  final key = UniqueKey();
  _HarborPageEntry(this.child, this.opacity);
}

class _HarborPageTransitionState extends State<HarborPageTransition>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, value: 1)
    ..addStatusListener(_onStatus);
  late final entries = [_HarborPageEntry(widget.child, 1)];
  double get progress => Curves.easeInOutCubic.transform(controller.value);

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && entries.length > 1) {
      setState(() => entries.removeRange(0, entries.length - 1));
    }
  }

  @override
  void didUpdateWidget(HarborPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Widget.canUpdate(entries.last.child, widget.child)) {
      entries.last.child = widget.child;
      return;
    }
    // Freeze the entire visible composition until the latest page is opaque.
    // Independent outgoing timers can otherwise remove its backing canvas early.
    entries.last.opacity = progress;
    entries.add(_HarborPageEntry(widget.child, 0));
    controller.duration = harborMotion(context, 190);
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        for (final entry in entries)
          _HarborPageLayer(
            key: entry.key,
            opacity: entry == entries.last ? progress : entry.opacity,
            interactive: entry == entries.last && controller.isCompleted,
            child: entry.child,
          ),
      ],
    ),
  );
}

class _HarborPageLayer extends StatelessWidget {
  final double opacity;
  final bool interactive;
  final Widget child;
  const _HarborPageLayer({
    super.key,
    required this.opacity,
    required this.interactive,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !interactive,
    child: ExcludeFocus(
      excluding: !interactive,
      child: ExcludeSemantics(
        excluding: !interactive,
        child: FadeTransition(
          opacity: AlwaysStoppedAnimation(opacity),
          child: ColoredBox(
            color: HarborColors.of(context).background,
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// A single selection backdrop moves between rows using the same spring as
/// CupertinoSlidingSegmentedControl, which powers the Settings sliders.
class HarborSidebarNavigation extends StatelessWidget {
  final int? selectedIndex;
  final List<HarborNavItem> children;
  const HarborSidebarNavigation({
    super.key,
    required this.selectedIndex,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => _HarborSlidingNavigationScope(
    child: HarborSelectionSlide(
      selectedOffset: selectedIndex == null ? null : selectedIndex! * 43.0,
      height: 37,
      color: HarborColors.of(context).accent.withValues(alpha: 0.12),
      backdropKey: const ValueKey('sidebar-selection-backdrop'),
      children: [
        Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              SizedBox(height: 37, child: children[i]),
            ],
          ],
        ),
      ],
    ),
  );
}

/// Non-null destinations slide within a group; entering/leaving a group fades
/// at its own destination rather than travelling through unrelated rows.
class HarborSelectionSlide extends StatefulWidget {
  final double? selectedOffset;
  final double height;
  final Color color;
  final Key? backdropKey;
  final bool foreground;
  final List<Widget> children;
  const HarborSelectionSlide({
    super.key,
    required this.selectedOffset,
    required this.height,
    required this.color,
    this.backdropKey,
    this.foreground = false,
    required this.children,
  });
  @override
  State<HarborSelectionSlide> createState() => _HarborSelectionSlideState();
}

class _HarborSelectionSlideState extends State<HarborSelectionSlide>
    with TickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, value: 1);
  late final fade = AnimationController(
    vsync: this,
    value: widget.selectedOffset == null ? 0 : 1,
  );
  final ghosts = <({Key key, double offset, double opacity, Color color})>[];
  late double from = widget.selectedOffset ?? 0;
  late double to = from;
  double get offset => from + (to - from) * controller.value;
  @override
  void didUpdateWidget(HarborSelectionSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedOffset == widget.selectedOffset) return;
    final current = offset;
    final duration = harborMotion(context, 190);
    if (oldWidget.selectedOffset == null &&
        widget.selectedOffset != null &&
        current != widget.selectedOffset &&
        fade.value > 0 &&
        duration != Duration.zero) {
      ghosts.add((
        key: UniqueKey(),
        offset: current,
        opacity: fade.value,
        color: oldWidget.color,
      ));
      fade.value = 0;
    }
    fade.animateTo(
      widget.selectedOffset == null ? 0 : 1,
      duration: duration,
      curve: Curves.easeInOutCubic,
    );
    controller.stop();
    from = current;
    if (widget.selectedOffset == null) {
      to = current;
      controller.value = 1;
      return;
    }
    to = widget.selectedOffset!;
    if (oldWidget.selectedOffset == null ||
        harborMotion(context, 412) == Duration.zero) {
      from = to;
      controller.value = 1;
      return;
    }
    controller.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 503.551, damping: 44.8799),
        0,
        1,
        0,
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.hardEdge,
    children: [
      if (widget.foreground) ...widget.children,
      for (final ghost in ghosts)
        Positioned(
          key: ghost.key,
          left: 0,
          right: 0,
          top: ghost.offset,
          height: widget.height,
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: ghost.opacity, end: 0),
              duration: harborMotion(context, 190),
              curve: Curves.easeInOutCubic,
              onEnd: () {
                if (mounted) setState(() => ghosts.remove(ghost));
              },
              builder: (_, value, child) =>
                  Opacity(opacity: value, child: child),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ghost.color,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ),
      AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Positioned(
          left: 0,
          right: 0,
          top: offset,
          height: widget.height,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: fade,
              child: DecoratedBox(
                key: widget.backdropKey,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ),
      ),
      if (!widget.foreground) ...widget.children,
    ],
  );
}

class _HarborSlidingNavigationScope extends InheritedWidget {
  const _HarborSlidingNavigationScope({required super.child});
  @override
  bool updateShouldNotify(_HarborSlidingNavigationScope oldWidget) => false;
}

class HarborNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;
  const HarborNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });
  @override
  State<HarborNavItem> createState() => _HarborNavItemState();
}

class _HarborNavItemState extends State<HarborNavItem> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final selected = widget.selected;
    final sliding =
        context
            .dependOnInheritedWidgetOfExactType<
              _HarborSlidingNavigationScope
            >() !=
        null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () {
          if (!widget.selected) widget.onTap();
        },
        pressedOpacity: 1,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1 : 0),
          duration: harborMotion(context, 190),
          curve: Curves.easeInOutCubic,
          builder: (context, selection, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Color.lerp(
                hovered
                    ? colors.text.withValues(alpha: 0.055)
                    : Colors.transparent,
                sliding
                    ? Colors.transparent
                    : colors.accent.withValues(alpha: 0.12),
                selection,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 15,
                  color: Color.lerp(
                    hovered ? colors.text : colors.muted,
                    colors.accent,
                    selection,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color.lerp(
                        hovered ? colors.text : colors.muted,
                        colors.accent,
                        selection,
                      ),
                    ),
                  ),
                ),
                if (widget.trailing != null)
                  Text(
                    widget.trailing!,
                    style: TextStyle(
                      fontSize: 10,
                      color: Color.lerp(
                        hovered ? colors.text : colors.muted,
                        colors.text,
                        selection,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HostMonogram extends StatelessWidget {
  final SSHHost host;
  final double size;
  final Color color;
  const HostMonogram({
    super.key,
    required this.host,
    this.size = 38,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(size * 0.25),
    ),
    child:
        context.watch<SSHStore>().hostIcons[host.hostAlias] != null &&
            harborHostIcons.containsKey(
              context.watch<SSHStore>().hostIcons[host.hostAlias],
            )
        ? Icon(
            harborHostIcons[context
                .watch<SSHStore>()
                .hostIcons[host.hostAlias]],
            size: size * 0.52,
            color: color,
          )
        : Text(
            host.hostAlias.isEmpty
                ? '?'
                : String.fromCharCode(host.hostAlias.runes.first).toUpperCase(),
            style: TextStyle(
              fontSize: size * 0.39,
              fontWeight: FontWeight.w600,
              color: HarborColors.of(context).dark
                  ? color
                  : Color.lerp(color, Colors.black, 0.35),
            ),
          ),
  );
}

class HarborWorkbench extends StatelessWidget {
  final ValueChanged<SSHHost> onSelect;
  final SSHActivityMonitor monitor;
  final VoidCallback onViewActivity;
  const HarborWorkbench({
    super.key,
    required this.onSelect,
    required this.monitor,
    required this.onViewActivity,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final colors = HarborColors.of(context);
    final favorites = store.hosts.where(store.isFavorite).toList();
    final featured = favorites.isEmpty
        ? store.hosts.take(4).toList()
        : favorites.take(6).toList();
    final recent = store.recentHosts
        .where((alias) => store.hosts.any((host) => host.hostAlias == alias))
        .map(
          (alias) => store.hosts.firstWhere((host) => host.hostAlias == alias),
        )
        .take(4)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 660;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 24 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'WORKBENCH',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                      color: colors.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'ON YOUR MAC',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.3,
                      color: colors.muted,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Icon(
                    CupertinoIcons.lock,
                    size: 11,
                    color: HarborColors.teal,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connection desk',
                          style: TextStyle(
                            fontSize: compact ? 24 : 28,
                            letterSpacing: -0.8,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pick a host. Get to work.',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  HarborButton(
                    label: 'Quick connect',
                    icon: CupertinoIcons.arrow_up_right,
                    onPressed: () => showQuickConnect(context),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      context,
                      '${store.hosts.length}',
                      'CONNECTIONS',
                      HarborColors.copper,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _stat(
                      context,
                      '${favorites.length}',
                      'FAVORITES',
                      const Color(0xFFAA9BDC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _stat(
                      context,
                      monitor.error == null
                          ? '${monitor.entries.where((entry) => entry.connected).length}'
                          : '—',
                      'ACTIVE SSH',
                      HarborColors.teal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text(
                    favorites.isEmpty
                        ? 'Your connections'
                        : 'Pinned connections',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    favorites.isEmpty
                        ? 'STAR A HOST TO PIN IT'
                        : '${favorites.length} PINNED',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (featured.isEmpty)
                _empty(
                  context,
                  CupertinoIcons.plus_square,
                  'Your workspace starts here.',
                  'Add a connection using the sidebar.',
                )
              else
                LayoutBuilder(
                  builder: (context, box) {
                    final columns = box.maxWidth > 560 ? 2 : 1;
                    final width = (box.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final host in featured)
                          SizedBox(
                            width: width,
                            child: HarborHostCard(
                              host: host,
                              onSelect: () => onSelect(host),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 28),
              HarborActivityList(
                monitor: monitor,
                compact: true,
                onViewAll: onViewActivity,
              ),
              const SizedBox(height: 24),
              _recentSection(context, recent),
              const SizedBox(height: 24),
              Row(
                children: [
                  const HarborMark(size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Made for your local SSH workflow.',
                    style: TextStyle(fontSize: 10, color: colors.muted),
                  ),
                  const Spacer(),
                  Text(
                    '⌘K to connect',
                    style: TextStyle(fontSize: 10, color: colors.muted),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(BuildContext context, String value, String label, Color accent) {
    final colors = HarborColors.of(context);
    final accentColor = colors.dark
        ? accent
        : Color.lerp(accent, Colors.black, 0.25)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(15.5, 13.5, 15.5, 13.5),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.35),
              border: Border.all(color: colors.border, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: colors.dark
                        ? accent
                        : Color.lerp(accent, Colors.black, 0.35),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3,
            child: ColoredBox(color: accentColor),
          ),
        ],
      ),
    );
  }

  Widget _empty(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final colors = HarborColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.muted),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 11, color: colors.text)),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, height: 1.5, color: colors.muted),
          ),
        ],
      ),
    );
  }

  Widget _recentSection(BuildContext context, List<SSHHost> hosts) {
    final colors = HarborColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recently opened',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 12),
        if (hosts.isEmpty)
          _empty(
            context,
            CupertinoIcons.clock,
            'No recent connections yet.',
            'Hosts appear here after opening Terminal.',
          )
        else
          for (final host in hosts)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 9),
              minimumSize: Size.zero,
              onPressed: () => onSelect(host),
              child: Row(
                children: [
                  Icon(CupertinoIcons.clock, size: 13, color: colors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      host.hostAlias,
                      style: TextStyle(fontSize: 12, color: colors.text),
                    ),
                  ),
                  Icon(
                    CupertinoIcons.arrow_up_right,
                    size: 12,
                    color: colors.muted,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class HarborHostCard extends StatefulWidget {
  final SSHHost host;
  final VoidCallback onSelect;
  const HarborHostCard({super.key, required this.host, required this.onSelect});
  @override
  State<HarborHostCard> createState() => _HarborHostCardState();
}

class _HarborHostCardState extends State<HarborHostCard> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final store = context.watch<SSHStore>();
    final host = widget.host;
    final accent = store.colorForGroup(store.groupFor(host));
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: harborMotion(context, 120),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(
              color: hovered ? accent.withValues(alpha: 0.28) : colors.border,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HostMonogram(host: host, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host.hostAlias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            store.groupFor(host),
                            style: TextStyle(fontSize: 10, color: accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  HarborFavoriteButton(host: host, size: 14),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${host.hostName.isEmpty ? 'Host not configured' : host.hostName}${store.tagsFor(host).isEmpty ? '' : ' · ${store.tagsFor(host).map((tag) => '#$tag').join(' ')}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 10,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'SSH / ${host.port.isEmpty ? '22' : host.port}',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1,
                      color: colors.muted,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () => launchHostTerminal(context, store, host),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Connect',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          CupertinoIcons.arrow_up_right,
                          size: 12,
                          color: colors.accent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HarborOrbitPainter extends CustomPainter {
  const HarborOrbitPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = HarborColors.copper.withValues(alpha: 0.24);
    for (final radius in [48.0, 68.0, 85.0]) {
      canvas.drawCircle(center, radius, line);
    }
    for (final offset in [
      const Offset(-57, -37),
      const Offset(58, 35),
      const Offset(-36, 57),
    ]) {
      canvas.drawLine(center, center + offset, line);
      canvas.drawCircle(center + offset, 5, Paint()..color = HarborColors.teal);
      canvas.drawCircle(center + offset, 9, line);
    }
    canvas.save();
    canvas.translate(center.dx - 30, center.dy - 30);
    HarborMarkPainter().paint(canvas, const Size.square(60));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<T?> showHarborSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) => showGeneralDialog<T>(
  context: context,
  barrierLabel: 'Dismiss panel',
  barrierDismissible: barrierDismissible,
  barrierColor: Colors.black.withValues(alpha: 0.35),
  transitionDuration: harborMotion(context, 120),
  pageBuilder: (context, _, _) => Center(child: builder(context)),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

class HarborQuickConnectTransition extends StatefulWidget {
  final Animation<double> animation;
  final Widget child;
  const HarborQuickConnectTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  State<HarborQuickConnectTransition> createState() =>
      _HarborQuickConnectTransitionState();
}

class _HarborQuickConnectTransitionState
    extends State<HarborQuickConnectTransition> {
  late CurvedAnimation opacity;
  void _configureOpacity() {
    opacity = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0, 0.3, curve: Curves.easeOut),
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _configureOpacity();
  }

  @override
  void didUpdateWidget(HarborQuickConnectTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      opacity.dispose();
      _configureOpacity();
    }
  }

  @override
  void dispose() {
    opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) {
      final progress = Curves.easeInOutCubic.transform(widget.animation.value);
      final remaining = 1 - progress;
      return Opacity(
        opacity: opacity.value,
        child: Transform.translate(
          offset: Offset(0, 10 * remaining),
          child: Transform.scale(
            scale: 1 + 0.08 * remaining,
            child: ImageFiltered(
              enabled: remaining > 0.001,
              imageFilter: ImageFilter.blur(
                sigmaX: 7 * remaining,
                sigmaY: 7 * remaining,
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

Future<T?> showHarborDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierLabel: 'Dismiss dialog',
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: builder(context)),
      ),
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class HarborAlert extends StatelessWidget {
  final Widget appIcon;
  final Widget title;
  final Widget message;
  final Widget primaryButton;
  final Widget? secondaryButton;
  final Widget? tertiaryButton;
  const HarborAlert({
    super.key,
    required this.appIcon,
    required this.title,
    required this.message,
    required this.primaryButton,
    this.secondaryButton,
    this.tertiaryButton,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 48,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.text.withValues(alpha: 0.055),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconTheme(
                        data: IconThemeData(size: 18, color: colors.muted),
                        child: appIcon,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: colors.text,
                      ),
                      child: title,
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        child: DefaultTextStyle(
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: colors.muted,
                          ),
                          child: message,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (tertiaryButton != null)
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          tertiaryButton!,
                          if (secondaryButton != null) secondaryButton!,
                          primaryButton,
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (secondaryButton != null) ...[
                            Flexible(child: secondaryButton!),
                            const SizedBox(width: 10),
                          ],
                          Flexible(child: primaryButton),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> confirmDeleteHost(
  BuildContext context,
  SSHStore store,
  SSHHost host,
) async {
  final confirmed = await showHarborDialog<bool>(
    context: context,
    builder: (dialogContext) => HarborAlert(
      appIcon: const Icon(
        CupertinoIcons.trash,
        color: CupertinoColors.destructiveRed,
      ),
      title: const Text('Delete connection?'),
      message: Text(
        '“${host.hostAlias}” will be removed from your SSH configuration.\nThe remote server and its files will stay untouched.',
      ),
      secondaryButton: HarborButton(
        label: 'Cancel',
        secondary: true,
        onPressed: () => Navigator.pop(dialogContext, false),
      ),
      primaryButton: HarborButton(
        label: 'Delete connection',
        color: CupertinoColors.destructiveRed,
        onPressed: () => Navigator.pop(dialogContext, true),
      ),
    ),
  );
  if (confirmed == true) store.deleteHost(host);
}

class HarborTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String? placeholder;
  final Widget? prefix;
  final bool readOnly;
  final bool autofocus;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final String? Function(String)? validator;
  final ValueChanged<String>? onSubmitted;
  const HarborTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.placeholder,
    this.prefix,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.onChanged,
    this.validator,
    this.onSubmitted,
  });
  @override
  State<HarborTextField> createState() => _HarborTextFieldState();
}

class _HarborTextFieldState extends State<HarborTextField> {
  TextEditingController? _ownedController;
  String? _error;
  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  Future<void> _autofocusWhenReady() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    while (mounted && widget.autofocus && !_focus.canRequestFocus) {
      if (route?.isCurrent == false) return;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted && widget.autofocus && route?.isCurrent != false) {
      _focus.requestFocus();
    }
  }

  TextEditingController get _controller =>
      widget.controller ?? _ownedController!;
  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = TextEditingController(text: widget.initialValue);
    }
    if (widget.autofocus) _autofocusWhenReady();
  }

  @override
  void didUpdateWidget(HarborTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) _autofocusWhenReady();
    if (widget.controller == null) {
      _ownedController ??= TextEditingController(text: widget.initialValue);
      final value = widget.initialValue ?? '';
      if (oldWidget.initialValue != widget.initialValue &&
          _controller.text != value) {
        _controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    } else if (_ownedController != null) {
      _ownedController!.dispose();
      _ownedController = null;
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final field = MacosTextField(
      controller: _controller,
      focusNode: _focus,
      placeholder: widget.placeholder,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      onChanged: (value) {
        setState(() => _error = widget.validator?.call(value));
        widget.onChanged?.call(value);
      },
      onSubmitted: widget.onSubmitted,
      prefix: widget.prefix == null
          ? null
          : IconTheme(
              data: IconThemeData(size: 16, color: colors.muted),
              child: DefaultTextStyle(
                style: TextStyle(fontSize: 12, color: colors.muted),
                child: widget.prefix!,
              ),
            ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      style: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: widget.readOnly ? colors.muted : colors.text,
      ),
      placeholderStyle: TextStyle(
        fontSize: 13,
        color: colors.muted.withValues(alpha: 0.75),
      ),
      cursorColor: colors.accent,
      decoration: BoxDecoration(
        color: colors.text.withValues(alpha: widget.readOnly ? 0.025 : 0.045),
        borderRadius: BorderRadius.circular(9),
        // macos_ui removes this decoration on focus. Paint the outline
        // without border insets so focusing cannot change field dimensions.
        boxShadow: [
          BoxShadow(
            color: colors.border.withValues(alpha: 0.6),
            spreadRadius: 0.75,
          ),
        ],
      ),
      focusedDecoration: BoxDecoration(
        color: colors.text.withValues(alpha: widget.readOnly ? 0.025 : 0.045),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: colors.accent.withValues(alpha: 0.7),
          width: 1,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: const TextStyle(
                fontSize: 11,
                color: CupertinoColors.destructiveRed,
              ),
            ),
          ),
      ],
    );
  }
}

const harborHostIcons = <String, IconData>{
  'Server': CupertinoIcons.cube_box,
  'Desktop': CupertinoIcons.desktopcomputer,
  'Laptop': CupertinoIcons.device_laptop,
  'Cloud': CupertinoIcons.cloud,
  'Database': CupertinoIcons.layers,
  'Code': CupertinoIcons.chevron_left_slash_chevron_right,
  'Network': CupertinoIcons.globe,
  'Shield': CupertinoIcons.shield,
  'Home': CupertinoIcons.house,
  'Lab': CupertinoIcons.lab_flask,
};

const harborGroupIcons = <String, IconData>{
  'Folder': CupertinoIcons.folder_fill,
  'Briefcase': CupertinoIcons.briefcase_fill,
  'Server': CupertinoIcons.cube_box_fill,
  'Cloud': CupertinoIcons.cloud_fill,
  'Database': CupertinoIcons.layers_fill,
  'Network': CupertinoIcons.globe,
  'Code': CupertinoIcons.chevron_left_slash_chevron_right,
  'Shield': CupertinoIcons.shield_fill,
  'Lab': CupertinoIcons.lab_flask,
  'Home': CupertinoIcons.house_fill,
  'Archive': CupertinoIcons.archivebox_fill,
  'Build': CupertinoIcons.building_2_fill,
};

class HarborGroupHeader extends StatelessWidget {
  final String name;
  final int count;
  final bool collapsed;
  final bool highlighted;
  final bool plain;
  const HarborGroupHeader({
    super.key,
    required this.name,
    required this.count,
    required this.collapsed,
    this.highlighted = false,
    this.plain = false,
  });
  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final colors = HarborColors.of(context);
    final color = plain ? colors.muted : store.colorForGroup(name);
    final icon = name == 'Favorites'
        ? CupertinoIcons.star_fill
        : store.iconForGroup(name) ?? CupertinoIcons.folder_fill;
    return AnimatedContainer(
      duration: harborMotion(context, 100),
      margin: EdgeInsets.only(top: plain ? 10 : 4, bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: plain ? 4 : 5),
      decoration: BoxDecoration(
        color: plain
            ? (highlighted
                  ? colors.text.withValues(alpha: 0.06)
                  : Colors.transparent)
            : color.withValues(alpha: highlighted ? 0.26 : 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(
            collapsed
                ? CupertinoIcons.chevron_right
                : CupertinoIcons.chevron_down,
            size: 11,
            color: color,
          ),
          if (!plain) ...[
            const SizedBox(width: 8),
            Icon(icon, size: 14, color: color),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              plain ? name.toUpperCase() : name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: plain ? 10 : 12,
                fontWeight: plain ? FontWeight.w500 : FontWeight.w600,
                letterSpacing: plain ? 0.6 : 0,
                color: plain ? colors.muted : colors.text,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: plain ? 0.10 : 0.13),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('$count', style: TextStyle(fontSize: 10, color: color)),
          ),
        ],
      ),
    );
  }
}

Future<void> showHostIconPicker(
  BuildContext context,
  SSHStore store,
  SSHHost host,
) async {
  await showHarborDialog(
    context: context,
    builder: (dialogContext) => HarborAlert(
      appIcon: const Icon(CupertinoIcons.square_grid_2x2),
      title: const Text('Connection icon'),
      message: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in harborHostIcons.entries)
            Tooltip(
              message: entry.key,
              child: Semantics(
                label: entry.key,
                selected: store.hostIcons[host.hostAlias] == entry.key,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    store.setHostIcon(host, entry.key);
                    Navigator.pop(dialogContext);
                  },
                  child: Container(
                    width: 56,
                    height: 48,
                    decoration: BoxDecoration(
                      color: HarborColors.of(
                        context,
                      ).text.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(9),
                      border: store.hostIcons[host.hostAlias] == entry.key
                          ? Border.all(color: HarborColors.of(context).accent)
                          : null,
                    ),
                    child: Icon(
                      entry.value,
                      size: 23,
                      color: store.colorForGroup(store.groupFor(host)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      secondaryButton: HarborButton(
        label: 'Use initial',
        secondary: true,
        onPressed: () {
          store.setHostIcon(host, null);
          Navigator.pop(dialogContext);
        },
      ),
      primaryButton: HarborButton(
        label: 'Done',
        onPressed: () => Navigator.pop(dialogContext),
      ),
    ),
  );
}

Future<void> showGroupAppearancePicker(
  BuildContext context,
  SSHStore store,
  String group,
) async {
  await showHarborDialog(
    context: context,
    builder: (dialogContext) => HarborAlert(
      appIcon: const Icon(CupertinoIcons.paintbrush),
      title: Text(group),
      message: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final colors = HarborColors.of(context);
          final selectedColor = store.groupColors[group];
          final selectedIcon = store.groupIcons[group];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Color',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final entry in harborGroupPalette.entries)
                    Tooltip(
                      message: entry.key,
                      child: Semantics(
                        label: entry.key,
                        selected: selectedColor == entry.key,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              store.setGroupColor(group, entry.key),
                          child: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: entry.value,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selectedColor == entry.key
                                    ? colors.text
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: selectedColor == entry.key
                                ? const Icon(
                                    CupertinoIcons.checkmark_alt,
                                    size: 15,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Icon',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.muted,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in harborGroupIcons.entries)
                    Tooltip(
                      message: entry.key,
                      child: Semantics(
                        label: entry.key,
                        selected: selectedIcon == entry.key,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => store.setGroupIcon(group, entry.key),
                          child: Container(
                            width: 48,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.text.withValues(alpha: 0.045),
                              borderRadius: BorderRadius.circular(9),
                              border: selectedIcon == entry.key
                                  ? Border.all(
                                      color: store.colorForGroup(group),
                                    )
                                  : null,
                            ),
                            child: Icon(
                              entry.value,
                              size: 21,
                              color: store.colorForGroup(group),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
      secondaryButton: HarborButton(
        label: 'Reset',
        secondary: true,
        onPressed: () {
          store.setGroupColor(group, null);
          store.setGroupIcon(group, null);
        },
      ),
      primaryButton: HarborButton(
        label: 'Done',
        onPressed: () => Navigator.pop(dialogContext),
      ),
    ),
  );
}

Future<void> showNewGroupDialog(
  BuildContext context,
  SSHStore store, {
  SSHHost? host,
  String? renameFrom,
}) async {
  final controller = TextEditingController(text: renameFrom);
  final name = await showHarborDialog<String>(
    context: context,
    builder: (dialogContext) => HarborAlert(
      appIcon: const Icon(CupertinoIcons.folder_badge_plus),
      title: Text(renameFrom == null ? 'New group' : 'Rename group'),
      message: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            host == null
                ? 'Create a group for your connections.'
                : 'Create a group and move “${host.hostAlias}” into it.',
          ),
          const SizedBox(height: 16),
          HarborTextField(
            controller: controller,
            autofocus: true,
            placeholder: 'e.g. Production',
            onSubmitted: (value) {
              if (value.trim().isNotEmpty && value.trim() != 'Ungrouped') {
                Navigator.pop(dialogContext, value.trim());
              }
            },
          ),
        ],
      ),
      secondaryButton: HarborButton(
        label: 'Cancel',
        secondary: true,
        onPressed: () => Navigator.pop(dialogContext),
      ),
      primaryButton: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, _) => HarborButton(
          label: renameFrom == null ? 'Create group' : 'Save name',
          onPressed:
              value.text.trim().isEmpty || value.text.trim() == 'Ungrouped'
              ? null
              : () => Navigator.pop(dialogContext, value.text.trim()),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 150));
  controller.dispose();
  if (name != null) {
    if (renameFrom == null) {
      await store.createGroup(name);
    } else {
      await store.renameGroup(renameFrom, name);
    }
    if (host != null) await store.setGroup(host, name);
  }
}

String terminalCommandScript(String command) =>
    '#!/bin/zsh\n'
    'launch_dir=\${0:A:h}\n'
    'rm -- "\$0"\n'
    'rmdir -- "\$launch_dir"\n'
    'exec $command\n';

Future<void> confirmRemoveGroup(
  BuildContext context,
  SSHStore store,
  String name,
) async {
  final confirmed = await showHarborDialog<bool>(
    context: context,
    builder: (dialogContext) => HarborAlert(
      appIcon: const Icon(CupertinoIcons.folder),
      title: const Text('Remove group?'),
      message: Text(
        'Connections in “$name” will move to Ungrouped. Your connections will be kept.',
      ),
      secondaryButton: HarborButton(
        label: 'Cancel',
        secondary: true,
        onPressed: () => Navigator.pop(dialogContext, false),
      ),
      primaryButton: HarborButton(
        label: 'Remove group',
        color: CupertinoColors.destructiveRed,
        onPressed: () => Navigator.pop(dialogContext, true),
      ),
    ),
  );
  if (confirmed == true) await store.removeGroup(name);
}

class HarborMenuEntry {
  final String label;
  final IconData? icon;
  final String? shortcut;
  final bool destructive;
  final bool checked;
  final bool separator;
  final VoidCallback? onSelected;
  final List<HarborMenuEntry>? children;
  const HarborMenuEntry(
    this.label,
    this.icon, {
    this.shortcut,
    this.destructive = false,
    this.checked = false,
    this.onSelected,
    this.children,
  }) : separator = false;
  const HarborMenuEntry.separator()
    : label = '',
      icon = null,
      shortcut = null,
      destructive = false,
      checked = false,
      separator = true,
      onSelected = null,
      children = null;
}

class HarborContextMenu extends StatefulWidget {
  final Offset position;
  final List<HarborMenuEntry> entries;
  final VoidCallback onDismiss;
  const HarborContextMenu({
    super.key,
    required this.position,
    required this.entries,
    required this.onDismiss,
  });
  @override
  State<HarborContextMenu> createState() => _HarborContextMenuState();
}

class _HarborContextMenuState extends State<HarborContextMenu> {
  int selected = -1;
  int? submenu;
  int subSelected = -1;
  final FocusNode _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double heightFor(List<HarborMenuEntry> entries) =>
      12 +
      entries.fold<double>(0, (sum, entry) => sum + (entry.separator ? 9 : 32));
  void invokeEntry(HarborMenuEntry entry, int index, bool inSubmenu) {
    if (entry.children != null) {
      setState(() {
        submenu = index;
        subSelected = -1;
      });
    } else {
      entry.onSelected?.call();
    }
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && submenu != null) {
      setState(() {
        selected = submenu!;
        submenu = null;
      });
      return KeyEventResult.handled;
    }
    final inSubmenu = submenu != null;
    final entries = inSubmenu
        ? widget.entries[submenu!].children!
        : widget.entries;
    final index = inSubmenu ? subSelected : selected;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.tab) {
      final choices = [
        for (var i = 0; i < entries.length; i++)
          if (!entries[i].separator) i,
      ];
      final direction = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      final current = choices.indexOf(index);
      final next = choices[(current + direction) % choices.length];
      setState(() {
        if (inSubmenu) {
          subSelected = next;
        } else {
          selected = next;
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      if (index >= 0 &&
          (key != LogicalKeyboardKey.arrowRight ||
              entries[index].children != null)) {
        invokeEntry(entries[index], index, inSubmenu);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 ||
        (key == LogicalKeyboardKey.keyN &&
            HardwareKeyboard.instance.isMetaPressed)) {
      final shortcut = key == LogicalKeyboardKey.f2 ? 'F2' : '⌘N';
      for (final entry in widget.entries) {
        if (entry.shortcut == shortcut) {
          entry.onSelected?.call();
          break;
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget panel(
    List<HarborMenuEntry> entries, {
    required bool isSubmenu,
    required double maxHeight,
  }) {
    final colors = HarborColors.of(context);
    return Container(
      width: isSubmenu ? 216 : 252,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.dark ? const Color(0xFF202D3C) : const Color(0xFFFFFEFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colors.text.withValues(alpha: colors.dark ? 0.10 : 0.08),
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < entries.length; i++)
              if (entries[i].separator)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Container(
                    height: 1,
                    color: colors.text.withValues(alpha: 0.07),
                  ),
                )
              else
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() {
                    if (isSubmenu) {
                      subSelected = i;
                    } else {
                      selected = i;
                      submenu = entries[i].children != null ? i : null;
                      subSelected = -1;
                    }
                  }),
                  child: Semantics(
                    button: true,
                    label: entries[i].label,
                    selected: entries[i].checked,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => invokeEntry(entries[i], i, isSubmenu),
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: (isSubmenu ? subSelected == i : selected == i)
                              ? colors.text.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              entries[i].checked
                                  ? CupertinoIcons.check_mark
                                  : entries[i].icon,
                              size: 14,
                              color: entries[i].destructive
                                  ? CupertinoColors.destructiveRed
                                  : colors.muted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entries[i].label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: entries[i].destructive
                                      ? CupertinoColors.destructiveRed
                                      : colors.text,
                                ),
                              ),
                            ),
                            if (entries[i].shortcut != null)
                              Text(
                                entries[i].shortcut!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.muted,
                                ),
                              ),
                            if (entries[i].children != null)
                              Icon(
                                CupertinoIcons.chevron_right,
                                size: 10,
                                color: colors.muted,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final left = widget.position.dx.clamp(8.0, constraints.maxWidth - 260);
      final height = heightFor(
        widget.entries,
      ).clamp(0.0, constraints.maxHeight - 16);
      final top = widget.position.dy.clamp(
        8.0,
        constraints.maxHeight - height - 8,
      );
      final index = submenu;
      final subEntries = index == null ? null : widget.entries[index].children;
      final subHeight = subEntries == null
          ? 0.0
          : heightFor(subEntries).clamp(0.0, constraints.maxHeight - 16);
      final subTop =
          (top +
                  (index == null
                      ? 0
                      : heightFor(widget.entries.take(index).toList()) - 12))
              .clamp(8.0, constraints.maxHeight - subHeight - 8);
      final subLeft = left + 252 + 216 <= constraints.maxWidth - 8
          ? left + 252
          : left - 216;
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: handleKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                onSecondaryTap: widget.onDismiss,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: panel(
                widget.entries,
                isSubmenu: false,
                maxHeight: constraints.maxHeight - 16,
              ),
            ),
            if (subEntries != null)
              Positioned(
                left: subLeft,
                top: subTop,
                child: panel(
                  subEntries,
                  isSubmenu: true,
                  maxHeight: constraints.maxHeight - 16,
                ),
              ),
          ],
        ),
      );
    },
  );
}

Future<void> showRenameHostDialog(
  BuildContext context,
  SSHStore store,
  SSHHost host,
) async {
  final controller = TextEditingController(text: host.hostAlias);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
  final alias = await showHarborDialog<String>(
    context: context,
    builder: (dialogContext) => HarborAlert(
      appIcon: const Icon(CupertinoIcons.pencil),
      title: const Text('Rename connection'),
      message: HarborTextField(
        controller: controller,
        autofocus: true,
        placeholder: 'Connection name',
        validator: (value) => store.validateHostAlias(host, value),
        onSubmitted: (value) {
          if (store.validateHostAlias(host, value) == null) {
            Navigator.pop(dialogContext, value);
          }
        },
      ),
      secondaryButton: HarborButton(
        label: 'Cancel',
        secondary: true,
        onPressed: () => Navigator.pop(dialogContext),
      ),
      primaryButton: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, _) => HarborButton(
          label: 'Rename',
          onPressed:
              store.validateHostAlias(host, value.text) == null &&
                  value.text != host.hostAlias
              ? () => Navigator.pop(dialogContext, value.text)
              : null,
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 150));
  controller.dispose();
  if (alias != null) store.renameHost(host, alias);
}

class HarborHostDraggable extends StatefulWidget {
  final LibraryHostRow child;
  final bool? externalHover;
  final bool? externalAfter;
  final Offset? Function()? pointerPosition;
  final ValueChanged<SSHHost>? onDropBefore;
  final void Function(SSHHost, bool)? onDropAt;
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final int selectionCount;
  const HarborHostDraggable({
    super.key,
    required this.child,
    this.externalHover,
    this.externalAfter,
    this.pointerPosition,
    this.onDropBefore,
    this.onDropAt,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
    this.selectionCount = 1,
  });
  @override
  State<HarborHostDraggable> createState() => _HarborHostDraggableState();
}

class _HarborHostDraggableState extends State<HarborHostDraggable> {
  bool after = false;
  void update(DragTargetDetails<SSHHost> details) {
    final box = context.findRenderObject()! as RenderBox;
    final next =
        box.globalToLocal(widget.pointerPosition?.call() ?? details.offset).dy >
        box.size.height / 2 + 4;
    if (next != after) setState(() => after = next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = HarborColors.of(context);
      return DragTarget<SSHHost>(
        onWillAcceptWithDetails: (details) {
          update(details);
          return !identical(details.data, widget.child.host);
        },
        onMove: update,
        onAcceptWithDetails: (details) {
          update(details);
          if (widget.onDropAt != null) {
            widget.onDropAt!(details.data, after);
          } else {
            widget.onDropBefore?.call(details.data);
          }
        },
        builder: (_, candidates, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            Draggable<SSHHost>(
              data: widget.child.host,
              onDragStarted: widget.onDragStarted,
              onDragUpdate: (details) =>
                  widget.onDragUpdate?.call(details.globalPosition),
              onDragEnd: (_) => widget.onDragEnd?.call(),
              allowedButtonsFilter: (buttons) => buttons == 1,
              feedback: ChangeNotifierProvider<SSHStore>.value(
                value: context.read<SSHStore>(),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: 56,
                  child: _HarborHostDragPreview(
                    row: widget.child,
                    count: widget.selectionCount,
                  ),
                ),
              ),
              childWhenDragging: SizedBox(
                height: 56,
                child: Center(
                  child: Opacity(opacity: 0.3, child: widget.child),
                ),
              ),
              child: SizedBox(height: 56, child: Center(child: widget.child)),
            ),
            if (widget.externalHover ?? candidates.isNotEmpty)
              Positioned(
                left: 4,
                right: 4,
                top: (widget.externalAfter ?? after) ? null : -1,
                bottom: (widget.externalAfter ?? after) ? -1 : null,
                child: IgnorePointer(
                  child: Container(height: 2, color: colors.accent),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _HarborHostDragPreview extends StatelessWidget {
  final LibraryHostRow row;
  final int count;
  const _HarborHostDragPreview({required this.row, required this.count});
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: count > 1 ? 14 : 0, end: count > 1 ? 3 : 0),
      duration: harborMotion(context, 160),
      curve: Curves.easeOutCubic,
      builder: (_, offset, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          if (count > 1)
            for (final layer in [2, 1])
              Positioned.fill(
                top: offset * layer,
                bottom: -offset * layer,
                left: layer * 2.0,
                right: layer * 2.0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.sidebar,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: colors.border),
                  ),
                ),
              ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.sidebar,
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: LibraryHostRow(
                  host: row.host,
                  selected: row.selected,
                  onTap: () {},
                  onSecondaryTapUp: (_) {},
                ),
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              right: 5,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HarborSectionDrag {
  final String name;
  const HarborSectionDrag(this.name);
}

class HarborSectionDropTarget extends StatefulWidget {
  final String name;
  final bool? externalHover;
  final bool? externalAfter;
  final bool hostDrag;
  final Offset? Function()? pointerPosition;
  final ValueChanged<SSHHost> onDropHost;
  final void Function(String, bool) onDropSection;
  final Widget Function(bool) builder;
  const HarborSectionDropTarget({
    super.key,
    required this.name,
    this.externalHover,
    this.externalAfter,
    this.hostDrag = false,
    this.pointerPosition,
    required this.onDropHost,
    required this.onDropSection,
    required this.builder,
  });
  @override
  State<HarborSectionDropTarget> createState() =>
      _HarborSectionDropTargetState();
}

class _HarborSectionDropTargetState extends State<HarborSectionDropTarget> {
  bool after = false;
  void update(DragTargetDetails<Object> details) {
    final box = context.findRenderObject()! as RenderBox;
    final next =
        box
            .globalToLocal(widget.pointerPosition?.call() ?? details.offset)
            .dy >=
        box.size.height / 2;
    if (next != after) setState(() => after = next);
  }

  @override
  Widget build(BuildContext context) => DragTarget<Object>(
    onWillAcceptWithDetails: (details) {
      update(details);
      return details.data is SSHHost ||
          (details.data is HarborSectionDrag &&
              (details.data as HarborSectionDrag).name != widget.name);
    },
    onMove: update,
    onAcceptWithDetails: (details) {
      update(details);
      if (details.data is SSHHost) {
        widget.onDropHost(details.data as SSHHost);
      } else {
        widget.onDropSection((details.data as HarborSectionDrag).name, after);
      }
    },
    builder: (_, candidates, _) => SizedBox(
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.builder(
            widget.externalHover == null
                ? candidates.any((candidate) => candidate is SSHHost)
                : widget.externalHover! && widget.hostDrag,
          ),
          if (widget.externalHover == null
              ? candidates.any((candidate) => candidate is HarborSectionDrag)
              : widget.externalHover! && !widget.hostDrag)
            Positioned(
              left: 4,
              right: 4,
              top: (widget.externalAfter ?? after) ? null : -1,
              bottom: (widget.externalAfter ?? after) ? -1 : null,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  color: HarborColors.of(context).accent,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class HarborSectionDraggable extends StatelessWidget {
  final String name;
  final HarborGroupHeader child;
  final VoidCallback? onDragStarted;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;
  const HarborSectionDraggable({
    super.key,
    required this.name,
    required this.child,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Draggable<HarborSectionDrag>(
      data: HarborSectionDrag(name),
      allowedButtonsFilter: (buttons) => buttons == 1,
      onDragStarted: onDragStarted,
      onDragUpdate: (details) => onDragUpdate?.call(details.globalPosition),
      onDragEnd: (_) => onDragEnd?.call(),
      feedback: SizedBox(width: constraints.maxWidth, height: 40, child: child),
      childWhenDragging: SizedBox(
        height: 40,
        child: Opacity(opacity: 0.35, child: child),
      ),
      child: SizedBox(height: 40, child: child),
    ),
  );
}

class _HarborSidebarInsertion extends StatefulWidget {
  final bool animate;
  final Widget child;
  const _HarborSidebarInsertion({required this.animate, required this.child});
  @override
  State<_HarborSidebarInsertion> createState() =>
      _HarborSidebarInsertionState();
}

class _HarborSidebarInsertionState extends State<_HarborSidebarInsertion>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    value: widget.animate ? 0 : 1,
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      controller.duration = harborMotion(context, 280);
      if (widget.animate) controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (_, child) {
      final value = Curves.easeInOutCubic.transform(controller.value);
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -6 * (1 - value)),
          child: child,
        ),
      );
    },
  );
}

class HarborAnimatedHosts extends StatefulWidget {
  final List<SSHHost> hosts;
  final Widget Function(SSHHost) itemBuilder;
  final Set<SSHHost> folded;
  final SSHHost? leader;
  final bool collapsed;
  final SSHHost? selectedHost;
  final bool animateSelection;
  const HarborAnimatedHosts({
    super.key,
    required this.hosts,
    required this.itemBuilder,
    this.folded = const {},
    this.leader,
    this.collapsed = false,
    this.selectedHost,
    this.animateSelection = false,
  });
  @override
  State<HarborAnimatedHosts> createState() => _HarborAnimatedHostsState();
}

class _HarborAnimatedHostsState extends State<HarborAnimatedHosts> {
  late final Set<SSHHost> known;
  @override
  void initState() {
    super.initState();
    known = widget.hosts.toSet();
  }

  Set<SSHHost> inserted = {};
  List<SSHHost> get hosts => widget.hosts;
  Set<SSHHost> get folded => widget.folded;
  SSHHost? get leader => widget.leader;
  SSHHost? get selectedHost => widget.selectedHost;
  bool get collapsed => widget.collapsed;
  bool get animateSelection => widget.animateSelection;
  Widget Function(SSHHost) get itemBuilder => widget.itemBuilder;
  @override
  void didUpdateWidget(HarborAnimatedHosts oldWidget) {
    super.didUpdateWidget(oldWidget);
    inserted = widget.hosts.toSet().difference(known);
    known
      ..clear()
      ..addAll(widget.hosts);
  }

  @override
  Widget build(BuildContext context) {
    final offsets = <SSHHost, double>{};
    double height = 0;
    for (final host in hosts) {
      offsets[host] = height;
      if (!folded.contains(host)) height += 56;
    }
    final anchor = offsets[leader] ?? 0;
    return IgnorePointer(
      ignoring: collapsed,
      child: ExcludeFocus(
        excluding: collapsed,
        child: ExcludeSemantics(
          excluding: collapsed,
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: collapsed ? 0.0 : height,
              end: collapsed ? 0.0 : height,
            ),
            duration: harborMotion(context, 280),
            curve: Curves.easeInOutCubic,
            builder: (_, value, child) => Offstage(
              offstage: value == 0,
              child: SizedBox(
                height: value,
                child: ClipRect(child: child),
              ),
            ),
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: height,
              maxHeight: height,
              child: SizedBox(
                height: height,
                child: HarborSelectionSlide(
                  selectedOffset:
                      animateSelection &&
                          !collapsed &&
                          selectedHost != null &&
                          !folded.contains(selectedHost)
                      ? offsets[selectedHost]
                      : null,
                  height: 53,
                  color: HarborColors.of(context).accent.withValues(
                    alpha: HarborColors.of(context).dark ? 0.16 : 0.12,
                  ),
                  backdropKey: const ValueKey('host-selection-backdrop'),
                  children: [
                    for (final host in hosts)
                      AnimatedPositioned(
                        key: ObjectKey(host),
                        duration: harborMotion(context, 280),
                        curve: Curves.easeInOutCubic,
                        top: folded.contains(host) ? anchor : offsets[host],
                        left: 0,
                        right: 0,
                        height: 56,
                        child: IgnorePointer(
                          ignoring: folded.contains(host),
                          child: AnimatedOpacity(
                            opacity: folded.contains(host) ? 0 : 1,
                            duration: harborMotion(context, 200),
                            child: Center(
                              child: _HarborSidebarInsertion(
                                animate: inserted.contains(host),
                                child: itemBuilder(host),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HarborForwardRule {
  final String type;
  final String value;
  const HarborForwardRule(this.type, this.value);
}

class HarborPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget secondaryAction;
  final Widget primaryAction;
  const HarborPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.secondaryAction,
    required this.primaryAction,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(width: 112, height: 40, child: secondaryAction),
          const SizedBox(width: 8),
          SizedBox(width: 156, height: 40, child: primaryAction),
        ],
      ),
    );
  }
}

class HarborConfigForwards extends StatelessWidget {
  final SSHHost host;
  const HarborConfigForwards({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final rules = <HarborForwardRule>[
      if (host.dynamicForward.isNotEmpty)
        HarborForwardRule('D', host.dynamicForward),
      for (final value in host.localForwards) HarborForwardRule('L', value),
      for (final value in host.remoteForwards) HarborForwardRule('R', value),
    ];
    Future<void> change(
      HarborForwardRule? previous,
      HarborForwardRule? next,
    ) async {
      if (previous != null) {
        if (previous.type == 'D') host.dynamicForward = '';
        if (previous.type == 'L') host.localForwards.remove(previous.value);
        if (previous.type == 'R') host.remoteForwards.remove(previous.value);
      }
      if (next != null) {
        if (next.type == 'D') {
          host.dynamicForward = next.value;
        } else if (next.type == 'L') {
          host.localForwards.add(next.value);
        } else if (next.type == 'R') {
          host.remoteForwards.add(next.value);
        }
      }
      store.markDirty(host.hostAlias);
      await store.saveConfig();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Port mapping')),
            HarborButton(
              label: 'Add mapping',
              secondary: true,
              onPressed: () => showAddMappingDialog(
                context,
                store,
                initialHost: host,
                onSave: (rule) => change(null, rule),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'These rules start with your SSH connection. Changes apply to the next connection.',
          style: TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
        ),
        for (final rule in rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    '${rule.type == 'D'
                        ? 'SOCKS5'
                        : rule.type == 'R'
                        ? 'Remote'
                        : 'Local'} · ${rule.value}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                CupertinoButton(
                  child: const Icon(CupertinoIcons.pencil, size: 16),
                  onPressed: () => showAddMappingDialog(
                    context,
                    store,
                    initialHost: host,
                    initialRule: rule,
                    onSave: (next) => change(rule, next),
                  ),
                ),
                CupertinoButton(
                  child: const Icon(CupertinoIcons.trash, size: 16),
                  onPressed: () => change(rule, null),
                ),
              ],
            ),
          ),
        if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No SSH config mappings.'),
          ),
      ],
    );
  }
}

class HarborForwardingPage extends StatefulWidget {
  const HarborForwardingPage({super.key});
  @override
  State<HarborForwardingPage> createState() => _HarborForwardingPageState();
}

class _HarborForwardingPageState extends State<HarborForwardingPage>
    with SingleTickerProviderStateMixin {
  String _query = '';
  String? _tag;
  final Set<String> _collapsed = {};

  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _rowKeys = <ManagedMapping, GlobalKey>{};
  final _groupKeys = <String, GlobalKey>{};
  final _selected = <ManagedMapping>{};
  List<ManagedMapping> _visible = [];
  List<ManagedMapping> _dragging = [];
  ManagedMapping? _anchor;
  ManagedMapping? _leader;
  Offset? _pointer;
  _MappingDrop? _drop;
  late final Ticker _scrollTicker;
  final _selectionFocus = FocusNode();
  final _searchFocus = FocusNode();
  bool _dragCancelled = false;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _scrollTicker = createTicker(_scrollDrag);
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) _clearSelection();
    });
  }

  Duration? _lastTick;

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(() {
      _selected.clear();
      _anchor = null;
    });
  }

  List<ManagedMapping> _scope(SSHStore store) => store.mappings
      .where((rule) => _selected.isEmpty || _selected.contains(rule))
      .toList();

  void _select(ManagedMapping rule) {
    _selectionFocus.requestFocus();
    final keyboard = HardwareKeyboard.instance;
    setState(() {
      if (keyboard.isShiftPressed &&
          _anchor != null &&
          _visible.contains(_anchor)) {
        final from = _visible.indexOf(_anchor!);
        final to = _visible.indexOf(rule);
        if (to < 0) return;
        if (!keyboard.isMetaPressed && !keyboard.isControlPressed) {
          _selected.clear();
        }
        _selected.addAll(
          _visible.sublist(from < to ? from : to, (from > to ? from : to) + 1),
        );
      } else if (keyboard.isMetaPressed || keyboard.isControlPressed) {
        if (!_selected.remove(rule)) _selected.add(rule);
        _anchor = rule;
      } else {
        _selected
          ..clear()
          ..add(rule);
        _anchor = rule;
      }
    });
  }

  Rect? _rect(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  _MappingDrop? _findDrop() {
    if (_dragCancelled) return null;
    final point = _pointer;
    final viewport = _rect(_viewport);
    if (point == null || viewport == null || !viewport.contains(point)) {
      return null;
    }
    for (final rule in _visible) {
      if (_dragging.contains(rule)) continue;
      final rect = _rect(_rowKeys[rule]);
      if (rect != null &&
          Rect.fromLTRB(
            rect.left,
            rect.top - 5,
            rect.right,
            rect.bottom + 5,
          ).contains(point)) {
        return _MappingDrop(
          rule.group,
          target: rule,
          after: point.dy > rect.center.dy,
        );
      }
    }
    for (final entry in _groupKeys.entries) {
      final rect = _rect(entry.value);
      if (rect != null && rect.contains(point)) return _MappingDrop(entry.key);
    }
    return null;
  }

  void _updateDrop() {
    final next = _findDrop();
    if (!(_drop?.matches(next) ?? next == null)) setState(() => _drop = next);
  }

  void _scrollDrag(Duration elapsed) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dragging.isNotEmpty) _updateDrop();
    });
    final previous = _lastTick;
    _lastTick = elapsed;
    final rect = _rect(_viewport);
    if (_pointer == null ||
        rect == null ||
        !_scroll.hasClients ||
        previous == null) {
      return;
    }
    if (_pointer!.dx < rect.left || _pointer!.dx > rect.right) return;
    final y = _pointer!.dy;
    final speed = y < rect.top + 64
        ? -((rect.top + 64 - y) / 64).clamp(0.0, 1.0)
        : y > rect.bottom - 64
        ? ((y - rect.bottom + 64) / 64).clamp(0.0, 1.0)
        : 0.0;
    if (speed == 0) return;
    final delta = (elapsed - previous).inMicroseconds / 1000000;
    final position = (_scroll.offset + speed * 650 * delta).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if (position != _scroll.offset) {
      _scroll.jumpTo(position);
    }
  }

  void _beginDrag(SSHStore store, ManagedMapping rule) {
    _selectionFocus.requestFocus();
    _dragCancelled = false;
    setState(() {
      if (!_selected.contains(rule)) {
        _selected
          ..clear()
          ..add(rule);
      }
      _anchor = rule;
      _leader = rule;
      _dragging = store.mappings.where(_selected.contains).toList();
    });
    _lastTick = null;
    _scrollTicker.start();
  }

  void _endDrag(SSHStore store) {
    final drop = _dragCancelled ? null : _findDrop();
    final moving = _dragging.toList();
    _scrollTicker.stop();
    setState(() {
      _dragging = [];
      _leader = null;
      _drop = null;
      _pointer = null;
    });
    if (drop != null) {
      setState(() => _collapsed.remove(drop.group));
      unawaited(
        store.moveMappings(
          moving,
          drop.group,
          target: drop.target,
          after: drop.after,
        ),
      );
    }
  }

  Future<void> _startSelection(SSHStore store) async {
    await _showStartErrors(await store.startMappings(_scope(store)));
  }

  Future<void> _showStartErrors(List<String> errors) async {
    if (errors.isEmpty || !mounted) return;
    await showHarborDialog(
      context: context,
      builder: (dialogContext) => HarborAlert(
        appIcon: const Icon(CupertinoIcons.exclamationmark_triangle),
        title: const Text('Some mappings could not start'),
        message: Text(errors.join('\n')),
        primaryButton: HarborButton(
          label: 'OK',
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollTicker.dispose();
    _selectionFocus.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _newGroup(
    SSHStore store, {
    ManagedMapping? mapping,
    List<ManagedMapping>? selection,
  }) async {
    final moving =
        selection ??
        (mapping == null
            ? <ManagedMapping>[]
            : _selected.contains(mapping)
            ? _scope(store)
            : [mapping]);
    final controller = TextEditingController();
    String? error(String name) {
      if (name.trim().isEmpty) return 'Enter a group name.';
      if (name.trim() == 'Ungrouped') return 'This name is reserved.';
      if (store.mappingGroupNames.contains(name.trim())) {
        return 'This group already exists.';
      }
      return null;
    }

    final name = await showHarborDialog<String>(
      context: context,
      builder: (dialogContext) => HarborAlert(
        appIcon: const Icon(CupertinoIcons.folder_badge_plus),
        title: const Text('New mapping group'),
        message: HarborTextField(
          controller: controller,
          autofocus: true,
          placeholder: 'Group name',
          validator: error,
          onSubmitted: (value) {
            if (error(value) == null) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        secondaryButton: HarborButton(
          label: 'Cancel',
          secondary: true,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        primaryButton: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) => HarborButton(
            label: 'Create group',
            onPressed: error(value.text) == null
                ? () => Navigator.pop(dialogContext, value.text.trim())
                : null,
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    controller.dispose();
    if (name == null) return;
    await store.createMappingGroup(name);
    if (mapping != null) {
      await store.moveMappings(moving, name);
    }
    if (mounted) {
      _searchController.clear();
      setState(() {
        _query = '';
        _tag = null;
        _collapsed.remove(name);
      });
    }
  }

  Future<void> _removeGroup(SSHStore store, String group) async {
    final confirmed = await showHarborDialog<bool>(
      context: context,
      builder: (dialogContext) => HarborAlert(
        appIcon: const Icon(CupertinoIcons.folder_badge_minus),
        title: const Text('Remove mapping group?'),
        message: Text(
          'Mappings in “$group” will move to Ungrouped. Running connections will stay active.',
        ),
        secondaryButton: HarborButton(
          label: 'Cancel',
          secondary: true,
          onPressed: () => Navigator.pop(dialogContext, false),
        ),
        primaryButton: HarborButton(
          label: 'Remove group',
          color: CupertinoColors.destructiveRed,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ),
    );
    if (confirmed == true) await store.renameMappingGroup(group, '');
  }

  Future<void> _toggleMapping(SSHStore store, ManagedMapping mapping) async {
    if (store.mappingLoading(mapping)) {
      await store.stopMapping(mapping);
      return;
    }
    final error = await store.toggleMapping(mapping);
    if (error != null && mounted) {
      await showHarborDialog(
        context: context,
        builder: (dialogContext) => HarborAlert(
          appIcon: const Icon(CupertinoIcons.exclamationmark_triangle),
          title: const Text('Could not start mapping'),
          message: Text(error),
          primaryButton: HarborButton(
            label: 'OK',
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ),
      );
    }
  }

  void _showContextMenu(
    Offset position,
    SSHStore store, {
    ManagedMapping? mapping,
    String? group,
  }) {
    if (mapping != null && !_selected.contains(mapping)) {
      setState(() {
        _selected
          ..clear()
          ..add(mapping);
        _anchor = mapping;
      });
    }
    final selection = _scope(store);
    final navigator = Navigator.of(context);
    void perform(VoidCallback action) {
      navigator.pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) action();
      });
    }

    final currentGroup = mapping?.group ?? group ?? '';
    final members = group == null
        ? <ManagedMapping>[]
        : store.mappings.where((rule) => rule.group == group).toList();
    final entries = <HarborMenuEntry>[
      if (mapping != null) ...[
        HarborMenuEntry(
          'Edit mapping…',
          CupertinoIcons.pencil,
          onSelected: store.mappingLoading(mapping) || store.hosts.isEmpty
              ? null
              : () => perform(
                  () => showAddMappingDialog(
                    context,
                    store,
                    initialMapping: mapping,
                  ),
                ),
        ),
        HarborMenuEntry(
          store.mappingRunning(mapping) || store.mappingLoading(mapping)
              ? (selection.length > 1 ? 'Stop selected' : 'Stop mapping')
              : (selection.length > 1 ? 'Start selected' : 'Start mapping'),
          store.mappingRunning(mapping) || store.mappingLoading(mapping)
              ? CupertinoIcons.stop_fill
              : CupertinoIcons.play_fill,
          onSelected: () => perform(() async {
            if (selection.length == 1) {
              await _toggleMapping(store, mapping);
            } else if (store.mappingRunning(mapping) ||
                store.mappingLoading(mapping)) {
              for (final rule in selection) {
                await store.stopMapping(rule);
              }
            } else {
              await _showStartErrors(await store.startMappings(selection));
            }
          }),
        ),
        HarborMenuEntry(
          'Move to group',
          CupertinoIcons.folder,
          children: [
            for (final name in store.mappingGroupNames)
              HarborMenuEntry(
                name,
                CupertinoIcons.folder,
                checked: mapping.group == name,
                onSelected: () =>
                    perform(() => store.moveMappings(selection, name)),
              ),
            HarborMenuEntry(
              'Ungrouped',
              CupertinoIcons.tray,
              checked: mapping.group.isEmpty,
              onSelected: () =>
                  perform(() => store.moveMappings(selection, '')),
            ),
            const HarborMenuEntry.separator(),
            HarborMenuEntry(
              'New group…',
              CupertinoIcons.folder_badge_plus,
              onSelected: () => perform(
                () => _newGroup(store, mapping: mapping, selection: selection),
              ),
            ),
          ],
        ),
        HarborMenuEntry(
          'Copy mapping value',
          CupertinoIcons.doc_on_doc,
          onSelected: () => perform(
            () => Clipboard.setData(ClipboardData(text: mapping.value)),
          ),
        ),
        const HarborMenuEntry.separator(),
      ],
      HarborMenuEntry(
        'New mapping',
        CupertinoIcons.plus,
        onSelected: store.hosts.isEmpty
            ? null
            : () => perform(
                () => showAddMappingDialog(
                  context,
                  store,
                  initialGroup: currentGroup,
                ),
              ),
      ),
      HarborMenuEntry(
        'New group…',
        CupertinoIcons.folder_badge_plus,
        onSelected: () => perform(() => _newGroup(store)),
      ),
      if (mapping == null && group != null) ...[
        const HarborMenuEntry.separator(),
        HarborMenuEntry(
          'Start group',
          CupertinoIcons.play_fill,
          onSelected:
              members.any(
                (rule) =>
                    !store.mappingRunning(rule) && !store.mappingLoading(rule),
              )
              ? () => perform(() => _startGroup(store, group))
              : null,
        ),
        HarborMenuEntry(
          'Stop group',
          CupertinoIcons.stop_fill,
          onSelected:
              members.any(
                (rule) =>
                    store.mappingRunning(rule) || store.mappingLoading(rule),
              )
              ? () => perform(() => store.stopMappingGroup(group))
              : null,
        ),
        if (group.isNotEmpty) ...[
          const HarborMenuEntry.separator(),
          HarborMenuEntry(
            'Rename group…',
            CupertinoIcons.pencil,
            onSelected: () => perform(() => _editGroup(store, group)),
          ),
          HarborMenuEntry(
            'Remove group…',
            CupertinoIcons.folder_badge_minus,
            destructive: true,
            onSelected: () => perform(() => _removeGroup(store, group)),
          ),
        ],
      ],
      if (mapping != null) ...[
        const HarborMenuEntry.separator(),
        HarborMenuEntry(
          selection.length > 1 ? 'Remove selected mappings' : 'Remove mapping',
          CupertinoIcons.trash,
          destructive: true,
          onSelected: () => perform(() async {
            for (final rule in selection) {
              await store.removeMapping(rule);
            }
            if (mounted) _clearSelection();
          }),
        ),
      ],
    ];
    _menuOpen = true;
    navigator
        .push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierDismissible: true,
            barrierColor: Colors.transparent,
            transitionDuration: harborMotion(context, 130),
            reverseTransitionDuration: harborMotion(context, 110),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                      child: child,
                    ),
            pageBuilder: (_, _, _) => HarborContextMenu(
              position: position,
              entries: entries,
              onDismiss: navigator.pop,
            ),
          ),
        )
        .whenComplete(() {
          _menuOpen = false;
        });
  }

  Future<void> _editGroup(SSHStore store, String group) async {
    final controller = TextEditingController(text: group);
    final next = await showHarborDialog<String>(
      context: context,
      builder: (dialogContext) => HarborAlert(
        appIcon: const Icon(CupertinoIcons.folder),
        title: const Text('Edit mapping group'),
        message: HarborTextField(
          controller: controller,
          autofocus: true,
          placeholder: 'Group name',
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        tertiaryButton: HarborButton(
          label: 'Ungroup',
          secondary: true,
          onPressed: () => Navigator.pop(dialogContext, ''),
        ),
        secondaryButton: HarborButton(
          label: 'Cancel',
          secondary: true,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        primaryButton: HarborButton(
          label: 'Save group',
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    controller.dispose();
    if (next != null) {
      await store.renameMappingGroup(group, next);
      if (mounted) setState(() => _collapsed.remove(group));
    }
  }

  Future<void> _startGroup(SSHStore store, String group) async {
    await _showStartErrors(await store.startMappingGroup(group));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final colors = HarborColors.of(context);
    final tags = store.mappings.expand((rule) => rule.tags).toSet().toList()
      ..sort();
    final selectedTag = tags.contains(_tag) ? _tag : null;
    final query = _query.trim().toLowerCase();
    final rules = store.mappings
        .where(
          (rule) =>
              (selectedTag == null || rule.tags.contains(selectedTag)) &&
              (query.isEmpty ||
                  '${rule.serverAlias} ${rule.group} ${rule.tags.join(' ')} ${rule.value}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
    final groups =
        {
          ...rules.map((rule) => rule.group),
          if (query.isEmpty && selectedTag == null) ...store.mappingGroupNames,
        }.toList()..sort(
          (a, b) => a.isEmpty
              ? 1
              : b.isEmpty
              ? -1
              : a.compareTo(b),
        );
    _selected.removeWhere((rule) => !rules.contains(rule));
    _visible = [
      for (final group in groups)
        if (!_collapsed.contains(group))
          ...rules.where((rule) => rule.group == group),
    ];
    _rowKeys.removeWhere((rule, _) => !store.mappings.contains(rule));
    _groupKeys.removeWhere((group, _) => !groups.contains(group));
    final scope = _scope(store);
    return TapRegion(
      onTapOutside: (_) {
        if (!_menuOpen) _clearSelection();
      },
      child: Focus(
        focusNode: _selectionFocus,
        onFocusChange: (focused) {
          if (!focused && mounted && !_menuOpen) _clearSelection();
        },
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _dragCancelled = true;
            setState(() => _drop = null);
            _clearSelection();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyA &&
              (HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isControlPressed) &&
              !_searchFocus.hasFocus) {
            setState(() => _selected.addAll(_visible));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerCancel: (_) => _dragCancelled = true,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              key: _viewport,
              behavior: HitTestBehavior.opaque,
              onTap: _clearSelection,
              onSecondaryTapUp: (details) =>
                  _showContextMenu(details.globalPosition, store),
              child: SingleChildScrollView(
                controller: _scroll,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HarborPageHeader(
                        title: 'Port forwarding',
                        subtitle:
                            '${store.mappings.length} independent mappings · ${groups.length} groups',
                        secondaryAction: HarborButton(
                          label: 'Stop all',
                          secondary: true,
                          fullWidth: true,
                          onPressed:
                              scope.any(
                                (rule) =>
                                    store.mappingRunning(rule) ||
                                    store.mappingLoading(rule),
                              )
                              ? () async {
                                  for (final rule in scope) {
                                    await store.stopMapping(rule);
                                  }
                                }
                              : null,
                        ),
                        primaryAction: HarborButton(
                          label: 'Add mapping',
                          icon: CupertinoIcons.plus,
                          fullWidth: true,
                          onPressed: store.hosts.isEmpty
                              ? null
                              : () => showAddMappingDialog(context, store),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          HarborButton(
                            key: const ValueKey('mapping-start-all'),
                            label: 'Start all',
                            icon: CupertinoIcons.play_fill,
                            secondary: true,
                            onPressed:
                                scope.any(
                                  (rule) =>
                                      !store.mappingRunning(rule) &&
                                      !store.mappingLoading(rule),
                                )
                                ? () => _startSelection(store)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selected.isEmpty
                                  ? 'All mappings'
                                  : '${_selected.length} selected',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.muted,
                              ),
                            ),
                          ),
                          if (_selected.isNotEmpty)
                            CupertinoButton(
                              padding: const EdgeInsets.all(6),
                              minimumSize: Size.zero,
                              onPressed: _clearSelection,
                              child: const Text(
                                'Clear selection',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      HarborTextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        placeholder: 'Search servers, groups, tags or ports…',
                        onChanged: (value) => setState(() {
                          _query = value;
                          _selected.clear();
                          _anchor = null;
                        }),
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final tag in <String?>[null, ...tags])
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                color: selectedTag == tag
                                    ? colors.accent.withValues(alpha: 0.13)
                                    : colors.surface,
                                onPressed: () => setState(() {
                                  _tag = tag;
                                  _selected.clear();
                                  _anchor = null;
                                }),
                                child: Text(
                                  tag == null ? 'All tags' : '#$tag',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.text,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (groups.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            store.mappings.isEmpty
                                ? 'Add an independent mapping, then assign a group and tags.'
                                : 'No mappings match this search.',
                            style: TextStyle(fontSize: 13, color: colors.muted),
                          ),
                        ),
                      for (final group in groups) ...[
                        _groupHeader(context, store, group),
                        const SizedBox(height: 10),
                        TweenAnimationBuilder<double>(
                          key: ValueKey('mapping-collapse:$group'),
                          tween: Tween(end: _collapsed.contains(group) ? 0 : 1),
                          duration: harborMotion(context, 280),
                          curve: Curves.easeInOutCubic,
                          builder: (_, factor, child) => ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: factor,
                              child: Offstage(
                                offstage: factor == 0,
                                child: IgnorePointer(
                                  ignoring: _collapsed.contains(group),
                                  child: ExcludeFocus(
                                    excluding: _collapsed.contains(group),
                                    child: ExcludeSemantics(
                                      excluding: _collapsed.contains(group),
                                      child: child!,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          child: _MappingSelectionList(
                            rules: rules
                                .where((rule) => rule.group == group)
                                .toList(),
                            selected: _selected.length == 1
                                ? _selected.single
                                : null,
                            builder: (rule) =>
                                _draggableRow(context, store, rule),
                          ),
                        ),
                        if (!_collapsed.contains(group) &&
                            !rules.any((rule) => rule.group == group))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No mappings in this group. Right-click its header to add one.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupHeader(BuildContext context, SSHStore store, String group) {
    final rules = store.mappings.where((rule) => rule.group == group).toList();
    final loading = rules.any(store.mappingLoading);
    final active = rules.any(
      (rule) => store.mappingRunning(rule) || store.mappingLoading(rule),
    );
    final allRunning = rules.every(store.mappingRunning);
    final running = rules.where(store.mappingRunning).length;
    final highlighted = _drop?.group == group && _drop?.target == null;
    return AnimatedContainer(
      key: _groupKeys.putIfAbsent(group, GlobalKey.new),
      duration: harborMotion(context, 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? HarborColors.of(context).dropTint
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted
              ? HarborColors.of(context).accent
              : Colors.transparent,
        ),
      ),
      child: GestureDetector(
        key: ValueKey('mapping-group:$group'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selected.clear();
          _anchor = null;
          if (!_collapsed.remove(group)) _collapsed.add(group);
        }),
        onSecondaryTapUp: (details) =>
            _showContextMenu(details.globalPosition, store, group: group),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.only(right: 8),
                  minimumSize: Size.zero,
                  onPressed: () => setState(() {
                    _selected.clear();
                    _anchor = null;
                    if (!_collapsed.remove(group)) _collapsed.add(group);
                  }),
                  child: AnimatedRotation(
                    turns: _collapsed.contains(group) ? -0.25 : 0,
                    duration: harborMotion(context, 220),
                    curve: Curves.easeInOutCubic,
                    child: const Icon(CupertinoIcons.chevron_down, size: 14),
                  ),
                ),
                Flexible(
                  child: Text(
                    group.isEmpty ? 'Ungrouped' : group,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$running/${rules.length} running',
                  style: const TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                HarborButton(
                  label: 'Start group',
                  secondary: true,
                  busy: loading,
                  onPressed: rules.isEmpty || allRunning || loading
                      ? null
                      : () => _startGroup(store, group),
                ),
                HarborButton(
                  label: 'Stop group',
                  secondary: true,
                  onPressed: active
                      ? () => store.stopMappingGroup(group)
                      : null,
                ),
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  onPressed: store.hosts.isEmpty
                      ? null
                      : () => showAddMappingDialog(
                          context,
                          store,
                          initialGroup: group,
                        ),
                  child: const Icon(CupertinoIcons.plus, size: 16),
                ),
                if (group.isNotEmpty)
                  CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                    onPressed: () => _editGroup(store, group),
                    child: const Icon(CupertinoIcons.pencil, size: 16),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _draggableRow(
    BuildContext context,
    SSHStore store,
    ManagedMapping rule,
  ) {
    final folded = _dragging.contains(rule) && _leader != rule;
    final insertion = _drop?.target == rule;
    return AnimatedSize(
      duration: harborMotion(context, 220),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: Align(
        heightFactor: folded ? 0 : 1,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LayoutBuilder(
            builder: (context, constraints) => Draggable<ManagedMapping>(
              data: rule,
              allowedButtonsFilter: (buttons) => buttons == 1,
              onDragStarted: () => _beginDrag(store, rule),
              onDragUpdate: (details) {
                _pointer = details.globalPosition;
                _updateDrop();
              },
              onDragEnd: (_) => _endDrag(store),
              feedback: _MappingDragPreview(
                rule: rule,
                count: _selected.contains(rule) ? _selected.length : 1,
                width: constraints.maxWidth.clamp(240, 600),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _mappingRow(context, store, rule),
              ),
              child: Stack(
                key: _rowKeys.putIfAbsent(rule, GlobalKey.new),
                clipBehavior: Clip.none,
                children: [
                  _mappingRow(context, store, rule),
                  if (insertion)
                    Positioned(
                      key: const ValueKey('mapping-insertion-line'),
                      left: 0,
                      right: 0,
                      top: _drop!.after ? null : -6,
                      bottom: _drop!.after ? -6 : null,
                      height: 2,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: HarborColors.of(context).accent,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mappingRow(
    BuildContext context,
    SSHStore store,
    ManagedMapping rule,
  ) {
    final colors = HarborColors.of(context);
    final running = store.mappingRunning(rule);
    final loading = store.mappingLoading(rule);
    return Semantics(
      selected: _selected.contains(rule),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(rule),
        onSecondaryTapUp: (details) =>
            _showContextMenu(details.globalPosition, store, mapping: rule),
        child: AnimatedContainer(
          duration: harborMotion(context, 180),
          key: ValueKey('mapping:${rule.id}'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _selected.length > 1 && _selected.contains(rule)
                ? Color.alphaBlend(colors.selectionTint, colors.surface)
                : colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selected.contains(rule)
                  ? colors.accent.withValues(alpha: 0.85)
                  : colors.border.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: HarborColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  rule.type == 'D'
                      ? CupertinoIcons.globe
                      : CupertinoIcons.arrow_right_arrow_left,
                  size: 17,
                  color: HarborColors.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${rule.serverAlias} · ${rule.type == 'D'
                          ? 'SOCKS5 proxy'
                          : rule.type == 'R'
                          ? 'Remote forward'
                          : 'Local forward'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      rule.type == 'D'
                          ? 'localhost:${rule.value}'
                          : '${rule.type == 'R' ? 'Server' : 'Mac'} ${rule.value.split(':').first} → ${rule.value.substring(rule.value.indexOf(':') + 1)}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Menlo',
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (rule.tags.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final tag in rule.tags)
                            GestureDetector(
                              onTap: () => setState(() {
                                _tag = tag;
                                _selected.clear();
                                _anchor = null;
                              }),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                    ],
                    Text(
                      loading
                          ? 'Starting…'
                          : running
                          ? 'Running'
                          : 'Stopped',
                      style: TextStyle(
                        fontSize: 10,
                        color: running ? HarborColors.teal : colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: HarborButton(
                  fullWidth: true,
                  label: loading
                      ? 'Starting…'
                      : running
                      ? 'Stop'
                      : 'Start',
                  secondary: true,
                  icon: running
                      ? CupertinoIcons.stop_fill
                      : CupertinoIcons.play_fill,
                  busy: loading,
                  onPressed: () => _toggleMapping(store, rule),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Edit mapping',
                child: CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  onPressed: loading || store.hosts.isEmpty
                      ? null
                      : () => showAddMappingDialog(
                          context,
                          store,
                          initialMapping: rule,
                        ),
                  child: Icon(
                    CupertinoIcons.pencil,
                    size: 15,
                    color: colors.muted,
                  ),
                ),
              ),
              Tooltip(
                message: 'Remove mapping',
                child: CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  onPressed: loading
                      ? null
                      : () async {
                          await store.removeMapping(rule);
                        },
                  child: Icon(
                    CupertinoIcons.trash,
                    size: 15,
                    color: colors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? validateMappingInput(
  SSHHost host,
  String type,
  String port,
  String remote,
  String remotePort,
) {
  final localNumber = int.tryParse(port);
  if (localNumber == null || localNumber < 1 || localNumber > 65535) {
    return type == 'R'
        ? 'Enter a server port between 1 and 65535.'
        : 'Enter a local port between 1 and 65535.';
  }
  if (type != 'D') {
    if (!RegExp(r'^(?:[A-Za-z0-9_.-]+|\[[0-9a-fA-F:]+\])$').hasMatch(remote)) {
      return 'Enter a target hostname or IP address.';
    }
    final remoteNumber = int.tryParse(remotePort);
    if (remoteNumber == null || remoteNumber < 1 || remoteNumber > 65535) {
      return 'Enter a target port between 1 and 65535.';
    }
  }
  return null;
}

class HarborServerSelector extends StatelessWidget {
  final SSHHost value;
  final ValueChanged<SSHHost> onChanged;
  const HarborServerSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return Builder(
      builder: (anchorContext) => CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 1,
        onPressed: () async {
          final store = context.read<SSHStore>();
          final box = anchorContext.findRenderObject()! as RenderBox;
          final origin = box.localToGlobal(Offset.zero);
          final screen = MediaQuery.sizeOf(context);
          final width = box.size.width;
          final height = (screen.height - 32).clamp(0.0, 310.0);
          final left = origin.dx.clamp(16.0, screen.width - width - 16);
          final top = (origin.dy + box.size.height + 6).clamp(
            16.0,
            screen.height - height - 16,
          );
          final selected = await showGeneralDialog<SSHHost>(
            context: context,
            barrierDismissible: true,
            barrierLabel: 'Close server picker',
            barrierColor: Colors.transparent,
            transitionDuration: harborMotion(context, 90),
            transitionBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            pageBuilder: (_, _, _) => ChangeNotifierProvider<SSHStore>.value(
              value: store,
              child: Stack(
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: _HarborServerPicker(selected: value),
                  ),
                ],
              ),
            ),
          );
          if (selected != null && context.mounted) onChanged(selected);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              HostMonogram(host: value, size: 30, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.hostAlias,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value.hostName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: colors.muted),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_down, size: 12, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _HarborServerPicker extends StatefulWidget {
  final SSHHost selected;
  const _HarborServerPicker({required this.selected});
  @override
  State<_HarborServerPicker> createState() => _HarborServerPickerState();
}

class _HarborServerPickerState extends State<_HarborServerPicker> {
  String query = '';
  int index = 0;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    index = context.read<SSHStore>().hosts.indexOf(widget.selected);
    WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
  }

  void reveal() {
    if (scroll.hasClients) {
      scroll.jumpTo((index * 52.0).clamp(0, scroll.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final colors = HarborColors.of(context);
    final hosts = store.hosts
        .where((host) => store.matchesHost(host, query))
        .toList();
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        if (hosts.isNotEmpty &&
            (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.arrowUp)) {
          setState(
            () => index =
                (index +
                    (event.logicalKey == LogicalKeyboardKey.arrowDown
                        ? 1
                        : -1)) %
                hosts.length,
          );
          reveal();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: HarborTextField(
                autofocus: true,
                placeholder: 'Search servers or groups…',
                prefix: Icon(
                  CupertinoIcons.search,
                  size: 14,
                  color: colors.muted,
                ),
                onChanged: (value) => setState(() {
                  query = value;
                  index = 0;
                }),
                onSubmitted: (_) {
                  if (hosts.isNotEmpty) Navigator.pop(context, hosts[index]);
                },
              ),
            ),
            Expanded(
              child: hosts.isEmpty
                  ? Center(
                      child: Text(
                        'No matching servers',
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                      itemExtent: 52,
                      itemCount: hosts.length,
                      itemBuilder: (context, row) {
                        final host = hosts[row];
                        return MouseRegion(
                          onEnter: (_) => setState(() => index = row),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.pop(context, host),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: row == index
                                    ? colors.accent.withValues(alpha: 0.10)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(
                                children: [
                                  HostMonogram(
                                    host: host,
                                    size: 28,
                                    color: colors.accent,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          host.hostAlias,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.text,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          host.hostName,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: colors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (identical(host, widget.selected))
                                    Icon(
                                      CupertinoIcons.check_mark,
                                      size: 13,
                                      color: colors.accent,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddMappingDialog(
  BuildContext context,
  SSHStore store, {
  SSHHost? initialHost,
  HarborForwardRule? initialRule,
  Future<void> Function(HarborForwardRule)? onSave,
  bool allowRemote = true,
  ManagedMapping? initialMapping,
  String initialGroup = '',
}) async {
  initialRule ??= initialMapping == null
      ? null
      : HarborForwardRule(initialMapping.type, initialMapping.value);
  var host =
      initialHost ??
      store.hosts
          .where((host) => host.hostAlias == initialMapping?.serverAlias)
          .firstOrNull ??
      store.hosts.first;
  final group = TextEditingController(
    text: initialMapping?.group ?? initialGroup,
  );
  final tags = TextEditingController(
    text: initialMapping?.tags.join(', ') ?? '',
  );
  final parts = initialRule?.value.split(':') ?? <String>[];
  final port = TextEditingController(text: parts.firstOrNull ?? '');
  final remote = TextEditingController(
    text: parts.length >= 3
        ? parts.sublist(1, parts.length - 1).join(':')
        : 'localhost',
  );
  final remotePort = TextEditingController(
    text: parts.length >= 3 ? parts.last : '',
  );
  var type = initialRule?.type ?? 'L';
  var edited = false;
  final rule = await showHarborDialog<HarborForwardRule>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) {
        final error = validateMappingInput(
          host,
          type,
          port.text.trim(),
          remote.text.trim(),
          remotePort.text.trim(),
        );
        void submit() {
          if (error == null) {
            Navigator.pop(
              dialogContext,
              HarborForwardRule(
                type,
                type == 'D'
                    ? int.parse(port.text.trim()).toString()
                    : '${int.parse(port.text.trim())}:${remote.text.trim()}:${int.parse(remotePort.text.trim())}',
              ),
            );
          }
        }

        return HarborAlert(
          appIcon: const Icon(CupertinoIcons.arrow_right_arrow_left),
          title: Text(
            initialRule == null ? 'Add port mapping' : 'Edit port mapping',
          ),
          message: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Server'),
              const SizedBox(height: 6),
              if (initialHost != null)
                Text(host.hostAlias)
              else
                HarborServerSelector(
                  value: host,
                  onChanged: (server) => update(() => host = server),
                ),
              const SizedBox(height: 16),
              HarborSegmentedControl<String>(
                groupValue: type,
                children: {
                  'L': const Text('Local'),
                  'D': const Text('SOCKS'),
                  if (allowRemote) 'R': const Text('Remote'),
                },
                onValueChanged: (value) => update(() {
                  type = value!;
                  edited = false;
                }),
              ),
              const SizedBox(height: 16),
              Text(
                type == 'R' ? 'Server listening port' : 'Local listening port',
              ),
              const SizedBox(height: 6),
              HarborTextField(
                controller: port,
                autofocus: true,
                placeholder: '8080',
                onChanged: (_) => update(() => edited = true),
                onSubmitted: (_) => submit(),
              ),
              if (type != 'D') ...[
                const SizedBox(height: 12),
                Text(
                  type == 'R'
                      ? 'Target host (from this Mac)'
                      : 'Target host (from server)',
                ),
                const SizedBox(height: 6),
                HarborTextField(
                  controller: remote,
                  placeholder: 'localhost',
                  onChanged: (_) => update(() => edited = true),
                ),
                const SizedBox(height: 12),
                const Text('Target port'),
                const SizedBox(height: 6),
                HarborTextField(
                  controller: remotePort,
                  placeholder: '80',
                  onChanged: (_) => update(() => edited = true),
                  onSubmitted: (_) => submit(),
                ),
              ],
              if (onSave == null) ...[
                const SizedBox(height: 12),
                const Text('Group'),
                const SizedBox(height: 6),
                HarborTextField(controller: group, placeholder: 'Ungrouped'),
                if (store.mappingGroupNames.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final name in store.mappingGroupNames)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          onPressed: () => group.text = name,
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                const Text('Tags (comma separated)'),
                const SizedBox(height: 6),
                HarborTextField(
                  controller: tags,
                  placeholder: 'work, database',
                ),
              ],
              if (edited && error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error,
                    style: const TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.destructiveRed,
                    ),
                  ),
                ),
            ],
          ),
          secondaryButton: HarborButton(
            label: 'Cancel',
            secondary: true,
            onPressed: () => Navigator.pop(dialogContext),
          ),
          primaryButton: HarborButton(
            label: initialRule == null ? 'Add mapping' : 'Save mapping',
            onPressed: error == null ? submit : null,
          ),
        );
      },
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 150));
  final groupValue = group.text.trim();
  final tagValues = tags.text.split(RegExp('[,，]'));
  group.dispose();
  tags.dispose();
  port.dispose();
  remote.dispose();
  remotePort.dispose();
  if (rule != null) {
    if (onSave != null) {
      await onSave(rule);
    } else if (initialMapping != null) {
      await store.updateMapping(
        initialMapping,
        host.hostAlias,
        rule.type,
        rule.value,
        group: groupValue,
        tags: tagValues,
      );
    } else {
      await store.addMapping(
        host.hostAlias,
        rule.type,
        rule.value,
        group: groupValue,
        tags: tagValues,
      );
    }
  }
}

class HarborAnimatedSections extends StatefulWidget {
  final List<MapEntry<String, List<SSHHost>>> sections;
  final Set<String> collapsed;
  final Set<SSHHost> folded;
  final Widget Function(MapEntry<String, List<SSHHost>>) sectionBuilder;
  const HarborAnimatedSections({
    super.key,
    required this.sections,
    required this.collapsed,
    this.folded = const {},
    required this.sectionBuilder,
  });
  @override
  State<HarborAnimatedSections> createState() => _HarborAnimatedSectionsState();
}

class _HarborAnimatedSectionsState extends State<HarborAnimatedSections> {
  late final Set<String> known;
  @override
  void initState() {
    super.initState();
    known = widget.sections.map((section) => section.key).toSet();
  }

  Set<String> inserted = {};
  List<MapEntry<String, List<SSHHost>>> get sections => widget.sections;
  Set<String> get collapsed => widget.collapsed;
  Set<SSHHost> get folded => widget.folded;
  Widget Function(MapEntry<String, List<SSHHost>>) get sectionBuilder =>
      widget.sectionBuilder;
  @override
  void didUpdateWidget(HarborAnimatedSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.sections.map((section) => section.key).toSet();
    inserted = next.difference(known);
    known
      ..clear()
      ..addAll(next);
  }

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No connections found',
          style: TextStyle(fontSize: 12, color: HarborColors.of(context).muted),
        ),
      );
    }
    double sectionHeight(MapEntry<String, List<SSHHost>> section) =>
        40 +
        (collapsed.contains(section.key)
            ? 0
            : section.value.where((host) => !folded.contains(host)).length *
                  56.0);
    final offsets = <double>[];
    var height = 0.0;
    for (final section in sections) {
      offsets.add(height);
      height += sectionHeight(section);
    }
    return AnimatedSize(
      duration: harborMotion(context, 280),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < sections.length; i++)
              AnimatedPositioned(
                key: ValueKey(sections[i].key),
                duration: harborMotion(context, 280),
                curve: Curves.easeInOutCubic,
                top: offsets[i],
                left: 0,
                right: 0,
                child: _HarborSidebarInsertion(
                  animate: inserted.contains(sections[i].key),
                  child: sectionBuilder(sections[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HarborSegmentedControl<T extends Object> extends StatelessWidget {
  final T groupValue;
  final Map<T, Widget> children;
  final ValueChanged<T?> onValueChanged;
  const HarborSegmentedControl({
    super.key,
    required this.groupValue,
    required this.children,
    required this.onValueChanged,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: groupValue,
      backgroundColor: colors.background,
      thumbColor: colors.dark ? const Color(0xFF35495F) : colors.surface,
      children: children.map(
        (key, child) => MapEntry(
          key,
          DefaultTextStyle.merge(
            style: TextStyle(color: colors.text),
            child: child,
          ),
        ),
      ),
      onValueChanged: onValueChanged,
    );
  }
}
