part of 'main.dart';

class _MappingDrop {
  final String group;
  final ManagedMapping? target;
  final bool after;
  const _MappingDrop(this.group, {this.target, this.after = false});
  bool matches(_MappingDrop? other) =>
      other != null &&
      group == other.group &&
      target == other.target &&
      after == other.after;
}

/// Measure real card heights: tags and narrow windows can wrap onto extra lines.
class _MappingSelectionList extends StatefulWidget {
  final List<ManagedMapping> rules;
  final ManagedMapping? selected;
  final Widget Function(ManagedMapping) builder;
  const _MappingSelectionList({
    required this.rules,
    required this.selected,
    required this.builder,
  });
  @override
  State<_MappingSelectionList> createState() => _MappingSelectionListState();
}

class _MappingSelectionListState extends State<_MappingSelectionList> {
  final _root = GlobalKey();
  final _keys = <ManagedMapping, GlobalKey>{};
  double? _top;
  double _height = 0;
  bool _scheduled = false;
  void _measureLater() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final root = _root.currentContext?.findRenderObject();
      final row = _keys[widget.selected]?.currentContext?.findRenderObject();
      double? top;
      var height = 0.0;
      if (root is RenderBox && row is RenderBox && row.hasSize) {
        top = row.localToGlobal(Offset.zero, ancestor: root).dy;
        height = (row.size.height - 10).clamp(0, double.infinity);
      }
      if (_top != top || _height != height) {
        setState(() {
          _top = top;
          _height = height;
        });
      }
      _keys.removeWhere((rule, _) => !widget.rules.contains(rule));
    });
  }

  @override
  Widget build(BuildContext context) {
    _measureLater();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _measureLater();
        return false;
      },
      child: HarborSelectionSlide(
        key: _root,
        selectedOffset: _top,
        height: _height,
        color: HarborColors.of(context).selectionTint,
        foreground: true,
        backdropKey: const ValueKey('mapping-selection-backdrop'),
        children: [
          Column(
            children: [
              for (final rule in widget.rules)
                SizeChangedLayoutNotifier(
                  key: _keys.putIfAbsent(rule, GlobalKey.new),
                  child: widget.builder(rule),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MappingDragPreview extends StatelessWidget {
  final ManagedMapping rule;
  final int count;
  final double width;
  const _MappingDragPreview({
    required this.rule,
    required this.count,
    required this.width,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: count > 1 ? 16 : 0, end: count > 1 ? 4 : 0),
      duration: harborMotion(context, 180),
      curve: Curves.easeOutCubic,
      builder: (_, offset, __) => SizedBox(
        width: width,
        height: 86 + offset * 2,
        child: Stack(
          children: [
            if (count > 1)
              for (final layer in [2, 1])
                Positioned(
                  left: layer * offset,
                  right: 0,
                  top: layer * offset,
                  height: 86,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
            Positioned(
              left: 0,
              right: offset * 2,
              top: 0,
              height: 86,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.accent),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.arrow_right_arrow_left,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${rule.serverAlias}\n${rule.value}',
                        maxLines: 2,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 12,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (count > 1)
                      Container(
                        key: const ValueKey('mapping-drag-count'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
