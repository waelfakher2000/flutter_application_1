import 'package:flutter/material.dart';

/// Reusable horizontally scrolling (marquee) text for overflowing titles.
class ScrollingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double gap;
  final double pixelsPerSecond;
  final bool enableWhenOverflow;
  const ScrollingText({
    super.key,
    required this.text,
    this.style,
    this.gap = 48,
    this.pixelsPerSecond = 60,
    this.enableWhenOverflow = true,
  });

  @override
  State<ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<ScrollingText> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _controller;
  double _textWidth = 0;
  double _lastTotalWidth = -1;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.forward(from: 0.0);
      }
    });
    _controller.addListener(() {
      if (!_scrollController.hasClients) return;
      final totalWidth = _textWidth + widget.gap;
      final double offset = _controller.value * totalWidth;
      _scrollController.jumpTo(offset);
    });
  }

  void _restart(double totalWidth) {
    _lastTotalWidth = totalWidth;
    final ms = (totalWidth / widget.pixelsPerSecond * 1000).clamp(800, 60000).toInt();
    _controller.duration = Duration(milliseconds: ms);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
      _controller.forward(from: 0.0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? Theme.of(context).textTheme.titleLarge;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        _textWidth = tp.width;
        final needsScroll = widget.enableWhenOverflow && _textWidth > constraints.maxWidth;
        if (!needsScroll) {
          if (_controller.isAnimating) _controller.stop();
          return Text(widget.text, style: style, overflow: TextOverflow.ellipsis, maxLines: 1);
        }
        final totalWidth = _textWidth + widget.gap;
        if (_lastTotalWidth != totalWidth) {
          _restart(totalWidth);
        } else if (!_controller.isAnimating) {
          _controller.forward(from: 0.0);
        }
        return SizedBox(
          height: (style?.fontSize ?? 20) * 1.4,
          child: ClipRect(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  Text(widget.text, style: style),
                  SizedBox(width: widget.gap),
                  Text(widget.text, style: style),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
