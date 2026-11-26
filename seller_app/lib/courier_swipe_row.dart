import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sadohod_shared_core/design_tokens.dart';
import 'courier_swipe_actions.dart';

/// One continuous gesture/animation controller for folder and product rows.
/// Drag samples write the current position directly. Only release animates.
/// The layout supplies its Figma endpoints; text never reflows during drag.
class CourierSwipeRow extends StatefulWidget {
  const CourierSwipeRow({
    super.key, required this.opened, required this.busy,
    required this.onReveal, required this.onOpen,
    required this.leadingAction, required this.trailingAction,
    required this.content,
    this.closedLeft = 0, this.openLeft = 0,
    this.closedRight = 0, this.actionInset = 0,
    this.travel = CourierSwipeAction.reveal,
    this.surfaceKey,
  });
  final bool opened, busy;
  final ValueChanged<bool> onReveal;
  final VoidCallback onOpen;
  final Widget leadingAction, trailingAction;
  final Widget Function(double progress) content;
  final double closedLeft, openLeft, closedRight, actionInset, travel;
  final Key? surfaceKey;

  @override
  State<CourierSwipeRow> createState() => _CourierSwipeRowState();
}

class _CourierSwipeRowState extends State<CourierSwipeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController position;
  bool dragging = false;
  double target = 0;

  @override
  void initState() {
    super.initState();
    target = widget.opened ? 1 : 0;
    position = AnimationController(vsync: this, value: target,
      duration: const Duration(milliseconds: 220));
  }

  @override
  void didUpdateWidget(covariant CourierSwipeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opened != widget.opened) {
      if (!widget.opened || !dragging) {
        dragging = false;
        settle(widget.opened);
      }
    }
    if (!oldWidget.busy && widget.busy && dragging) {
      dragging = false;
      settle(widget.opened);
    }
  }

  void settle(bool open, [double velocity = 0]) {
    final next = open ? 1.0 : 0.0;
    if (position.isAnimating && target == next) return;
    target = next;
    final distance = (target - position.value).abs();
    if (distance < .001) {
      position.value = target;
      return;
    }
    final speed = velocity.abs();
    final millis = (speed > 450
        ? distance * widget.travel / speed * 1000 + 100
        : 160 + 100 * distance).clamp(120, 260).round();
    position.animateTo(target, duration: Duration(milliseconds: millis),
      curve: Curves.easeOutCubic);
  }

  void start(DragStartDetails details) {
    position.stop();
    setState(() => dragging = true);
    // Claim this row at gesture start; any other row closes immediately.
    widget.onReveal(true);
  }

  void update(DragUpdateDetails details) {
    if (!dragging) return;
    position.value = (position.value - details.delta.dx / widget.travel)
        .clamp(0.0, 1.0).toDouble();
  }

  void end(DragEndDetails details) {
    if (!dragging) return;
    final velocity = details.primaryVelocity ?? 0;
    final projected = position.value - velocity * .12 / widget.travel;
    final open = position.value > .05 &&
        (velocity < -450 || (velocity <= 450 && projected >= .5));
    setState(() => dragging = false);
    settle(open, velocity);
    widget.onReveal(open);
  }

  void cancel() {
    if (!dragging) return;
    setState(() => dragging = false);
    settle(false);
    widget.onReveal(false);
  }

  @override
  void dispose() {
    position.dispose();
    super.dispose();
  }

  Widget revealAction(Widget action, double fraction) {
    final width = CourierSwipeAction.width;
    return SizedBox(width: width * fraction, height: CourierSwipeAction.height,
      child: ClipRect(child: OverflowBox(
        alignment: Alignment.centerRight, minWidth: width, maxWidth: width,
        child: Transform.scale(scale: .72 + .28 * fraction,
          alignment: Alignment.centerRight, child: action),
      )),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: CourierSwipeAction.height,
    child: LayoutBuilder(builder: (context, constraints) {
      final contentWidth = (constraints.maxWidth - widget.closedLeft -
          widget.closedRight).clamp(0.0, constraints.maxWidth).toDouble();
      return AnimatedBuilder(animation: position, builder: (context, _) {
        final t = position.value;
        final left = widget.closedLeft + (widget.openLeft-widget.closedLeft)*t;
        final openRight = widget.actionInset + CourierSwipeAction.reveal;
        final right = widget.closedRight + (openRight-widget.closedRight)*t;
        final trailing = (t*2).clamp(0.0,1.0).toDouble();
        final leading = (t*2-1).clamp(0.0,1.0).toDouble();
        final actionable = widget.opened && !dragging && !widget.busy && t >= .999;
        return ClipRect(child: Stack(clipBehavior: Clip.hardEdge, children: [
          if (t > 0)
            Positioned(right: widget.actionInset, top: 0, bottom: 0,
              child: ExcludeSemantics(excluding: !actionable,
                child: IgnorePointer(ignoring: !actionable,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (leading > 0) revealAction(widget.leadingAction, leading),
                    SizedBox(width: CourierSwipeAction.gap * leading),
                    revealAction(widget.trailingAction, trailing),
                  ]),
                ),
              ),
            ),
          Positioned(left: left, right: right, top: 0, bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTap: widget.busy ? null : () {
                if (position.value > .001) {
                  settle(false);
                  widget.onReveal(false);
                } else {
                  widget.onOpen();
                }
              },
              onHorizontalDragStart: widget.busy ? null : start,
              onHorizontalDragUpdate: widget.busy ? null : update,
              onHorizontalDragEnd: widget.busy ? null : end,
              onHorizontalDragCancel: cancel,
              child: DecoratedBox(
                key: widget.surfaceKey,
                decoration: BoxDecoration(
                  color: Color.lerp(SellerColors.background, const Color(0xffd9d9d9), t),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ClipRect(child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: contentWidth, maxWidth: contentWidth,
                  child: widget.content(t),
                )),
              ),
            ),
          ),
        ]));
      });
    }),
  );
}
