import 'package:flutter/material.dart';

/// A status light that sends out a slow ring while active.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, required this.pulsing, this.size = 16});

  final Color color;
  final bool pulsing;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (widget.pulsing)
                Container(
                  width: s * (1 + 1.6 * t),
                  height: s * (1 + 1.6 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color.withValues(alpha: 0.6 * (1 - t)), width: 1.5),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: widget.pulsing
                      ? [BoxShadow(color: widget.color.withValues(alpha: 0.55), blurRadius: 12, spreadRadius: 1)]
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
