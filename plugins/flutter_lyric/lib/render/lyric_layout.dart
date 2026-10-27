import 'package:flutter/rendering.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/core/lyric_style.dart';

class LyricLayout {
  final List<LineMetrics> metrics;
  final LyricStyle style;
  final Size viewSize;
  final double selectionAnchorPosition;
  final double activeAnchorPosition;

  /// 远端虚化用的「渐隐版」TextPainter 缓存 / Cached faded text painters.
  ///
  /// 逐行按与播放行的距离降低不透明度；布局在滚动过程中复用，故按
  /// (行号, 播放行) 缓存，避免逐帧重新排版。
  final Map<String, TextPainter> _defocusPainters = {};
  int _defocusPlayIndex = -999999;

  LyricLayout copyWith(LyricStyle style) {
    return LyricLayout._internal(
      metrics,
      style,
      viewSize,
      selectionAnchorPosition,
      activeAnchorPosition,
    );
  }

  @override
  String toString() {
    return 'LyricLayout(metrics: $metrics, style: $style)';
  }

  double lineOffsetY(int index, int activeIndex, double anchorPosition,
      MainAxisAlignment alignment) {
    double indexStartY = 0;
    for (var i = 0; i < metrics.length; i++) {
      final lineHeight = getLineHeight(i == activeIndex, i);
      if (i >= index) {
        final anchorOffset =
            anchorOffsetY(i, activeIndex == i, lineHeight, alignment);
        indexStartY += anchorOffset;
        break;
      }
      indexStartY += lineHeight + style.lineGap;
    }

    // 始终把目标行锚点（indexStartY）对齐到视口锚点（anchorPosition）：即使
    // 目标行在内容顶部（indexStartY < anchorPosition，返回负值，内容下移、当前
    // 行居中、上方留空），也保持居中，与主流歌词页一致。不再退回
    // -contentPadding.top——那会把首行顶到视口顶部（当前播放行在前几行时
    // 一直显示在顶部，直到行高累计越过锚点才跳回居中）。
    return indexStartY - anchorPosition;
  }

  // 用于修正Anchor对齐的偏移量
  double anchorAdjustmentOffsetY(int index, int activeIndex) {
    final isHighlight = index == activeIndex;
    final lineHeight = getLineHeight(isHighlight, index);
    var anchorOffset =
        anchorOffsetY(index, isHighlight, lineHeight, style.selectionAlignment);
    return (lineHeight / 2 - anchorOffset);
  }

  double anchorOffsetY(
    int index,
    bool isHighlight,
    double? lineHeight,
    MainAxisAlignment? alignment,
  ) {
    if (metrics.isEmpty || index < 0 || index >= metrics.length) return 0;
    final lh = lineHeight ?? getLineHeight(isHighlight, index);
    final hasTranslation = metrics[index].translationHeight > 0;
    final align = hasTranslation
        ? (alignment ?? style.selectionAlignment)
        : MainAxisAlignment.start;
    final currentLine = metrics[index];
    final activeHeight =
        isHighlight ? currentLine.activeHeight : currentLine.height;
    if (align == MainAxisAlignment.start) {
      return activeHeight / 2;
    } else if (align == MainAxisAlignment.end) {
      return activeHeight +
          style.translationLineGap +
          currentLine.translationHeight / 2;
    } else if (align == MainAxisAlignment.center) {
      // 居中锚点应对准「主歌词行」而不是整块（主行+翻译行）：带翻译时若按
      // 整块居中，主行会被顶到锚点上方，观感即「当前行没对准聚焦带中心」。
      // 这里让当前主行自身居中，翻译行自然垂在下方。
      return isHighlight ? activeHeight / 2 : lh / 2;
    }
    return 0;
  }

  double getLineHeight(bool isHighlight, int index) {
    if (metrics.isEmpty || index < 0 || index >= metrics.length) return 0;
    final mainHeight =
        isHighlight ? metrics[index].activeHeight : metrics[index].height;
    if (metrics[index].translationHeight == 0) {
      return mainHeight;
    }
    return mainHeight +
        metrics[index].translationHeight +
        style.translationLineGap;
  }

  double contentHeight(int highlightIndex) {
    double totalHeight = 0;
    for (var i = 0; i < metrics.length; i++) {
      totalHeight += getLineHeight(i == highlightIndex, i);
      if (i < metrics.length - 1) {
        totalHeight += style.lineGap;
      }
    }
    return totalHeight + style.contentPadding.vertical;
  }

  /// 远端虚化用的「渐隐版」TextPainter / Faded text painter for the defocus.
  ///
  /// 只改颜色不透明度，不改字号/字重，因此原有的行度量（词级高亮用的
  /// LineMetrics）依然有效。
  TextPainter? defocusPainter({
    required int index,
    required int playIndex,
    required bool isActive,
    required bool isTranslation,
    required double opacity,
  }) {
    if (index < 0 || index >= metrics.length) return null;
    if (opacity >= 0.999) return null;
    if (_defocusPlayIndex != playIndex) {
      _defocusPainters.clear();
      _defocusPlayIndex = playIndex;
    }
    final key = '$index|$isActive|$isTranslation';
    final cached = _defocusPainters[key];
    if (cached != null) return cached;
    final base = isTranslation
        ? metrics[index].translationTextPainter
        : (isActive
            ? metrics[index].activeTextPainter
            : metrics[index].textPainter);
    final span = base.text;
    if (span is! TextSpan) return null;
    final baseStyle = span.style;
    final color = baseStyle?.color;
    if (baseStyle == null || color == null) return null;
    final painter = TextPainter(
      text: TextSpan(
        text: span.toPlainText(),
        style: baseStyle.copyWith(
          color: color.withValues(alpha: color.a * opacity),
        ),
      ),
      textAlign: base.textAlign,
      textDirection: base.textDirection ?? TextDirection.ltr,
      maxLines: base.maxLines,
      ellipsis: base.ellipsis,
      locale: base.locale,
      strutStyle: base.strutStyle,
      textWidthBasis: base.textWidthBasis,
      textHeightBehavior: base.textHeightBehavior,
    )..layout(maxWidth: viewSize.width);
    _defocusPainters[key] = painter;
    return painter;
  }

  LyricLayout._internal(
    this.metrics,
    this.style,
    this.viewSize,
    this.selectionAnchorPosition,
    this.activeAnchorPosition,
  );

  factory LyricLayout.updatePainters(
    LyricLayout layout,
  ) {
    final lineMetrics = <LineMetrics>[];
    for (var line in layout.metrics) {
      line.textPainter.markNeedsLayout();
      line.activeTextPainter.markNeedsLayout();
      line.translationTextPainter.markNeedsLayout();
      line.textPainter.layout(maxWidth: layout.viewSize.width);
      line.activeTextPainter.layout(maxWidth: layout.viewSize.width);
      final hasTranslation = line.translationTextPainter.text != null;
      if (hasTranslation) {
        line.translationTextPainter.layout(maxWidth: layout.viewSize.width);
      }
      line.words;
      final words = _calcWordMetrics(line.line, line.textPainter,
          line.activeTextPainter, line.translationTextPainter);
      lineMetrics.add(line.copyWith(
        height: line.textPainter.height,
        width: line.textPainter.width,
        activeWidth: line.activeTextPainter.width,
        activeHeight: line.activeTextPainter.height,
        translationWidth:
            hasTranslation ? line.translationTextPainter.width : 0,
        translationHeight:
            hasTranslation ? line.translationTextPainter.height : 0,
        activeMetrics: line.activeTextPainter.computeLineMetrics(),
        metrics: line.textPainter.computeLineMetrics(),
        words: words,
      ));
    }
    return LyricLayout._internal(
      layout.metrics,
      layout.style,
      layout.viewSize,
      layout.selectionAnchorPosition,
      layout.activeAnchorPosition,
    );
  }

  static List<WordMetrics>? _calcWordMetrics(
      LyricLine line,
      TextPainter textPainter,
      TextPainter activeTextPainter,
      TextPainter translationTextPainter) {
    var currentOffset = 0;
    final words = line.words?.map((word) {
      // 从当前位置开始查找单词，确保按顺序匹配
      final wordStart = line.text.indexOf(word.text, currentOffset);
      if (wordStart == -1) {
        // 如果找不到单词，使用默认值
        return WordMetrics(
          word: word,
          width: 0,
          height: textPainter.height,
          highlightWidth: 0,
          highlightHeight: activeTextPainter.height,
        );
      }
      final wordEnd = wordStart + word.text.length;
      // 更新当前位置，为下一个单词查找做准备
      currentOffset = wordEnd;

      // 使用 textPainter 获取普通样式的文本框
      final textSelection =
          TextSelection(baseOffset: wordStart, extentOffset: wordEnd);
      final textBoxes = textPainter.getBoxesForSelection(textSelection);
      var tWidth = 0.0;
      var tHeight = 0.0;
      calcWordSize(List<TextBox> boxs) {
        tWidth = 0.0;
        tHeight = 0.0;
        var h = 0;
        for (var box in boxs) {
          final rect = box.toRect();
          tWidth += rect.width;
          if (rect.height > h) {
            tHeight = rect.height;
          }
        }
      }

      calcWordSize(textBoxes);
      final width = tWidth;
      final wordHeight = tHeight;

      // 使用 activeTextPainter 获取高亮样式的文本框
      final activeBoxes = activeTextPainter.getBoxesForSelection(textSelection);
      calcWordSize(activeBoxes);
      final highlightWidth = tWidth;
      final wordHighlightHeight = tHeight;

      return WordMetrics(
        word: word,
        width: width,
        height: wordHeight,
        highlightWidth: highlightWidth,
        highlightHeight: wordHighlightHeight,
      );
    }).toList();
    return words;
  }

  factory LyricLayout.compute(
    LyricModel model,
    LyricStyle style,
    Size viewSize,
  ) {
    final maxWidth = viewSize.width;
    final lineMetrics = <LineMetrics>[];
    for (var line in model.lines) {
      final textPainter = TextPainter(
        textAlign: style.lineTextAlign,
        textDirection: TextDirection.ltr,
      );
      final activeTextPainter = TextPainter(
        textAlign: style.lineTextAlign,
        textDirection: TextDirection.ltr,
      );
      final translationTextPainter = TextPainter(
        textAlign: style.lineTextAlign,
        textDirection: TextDirection.ltr,
      );
      textPainter.text = TextSpan(text: line.text, style: style.textStyle);
      textPainter.layout(maxWidth: maxWidth);

      final metrics = textPainter.computeLineMetrics();
      final height = textPainter.height;
      final width = textPainter.width;

      activeTextPainter.text =
          TextSpan(text: line.text, style: style.activeStyle);
      activeTextPainter.layout(maxWidth: maxWidth);
      final activceLineMetrics = activeTextPainter.computeLineMetrics();
      final highlightWidth = activeTextPainter.width;
      final highlightHeight = activeTextPainter.height;

      double translationWidth = 0;
      double translationHeight = 0;

      if (line.translation != null) {
        translationTextPainter.text = TextSpan(
          text: line.translation,
          style: style.translationStyle,
        );
        translationTextPainter.layout(maxWidth: maxWidth);
        translationWidth = translationTextPainter.width;
        translationHeight = translationTextPainter.height;
      }
      final words = _calcWordMetrics(
          line, textPainter, activeTextPainter, translationTextPainter);
      lineMetrics.add(
        LineMetrics(
          line: line,
          height: height,
          width: width,
          activeWidth: highlightWidth,
          activeHeight: highlightHeight,
          translationWidth: translationWidth,
          translationHeight: translationHeight,
          activeMetrics: activceLineMetrics,
          metrics: metrics,
          words: words,
          textPainter: textPainter,
          activeTextPainter: activeTextPainter,
          translationTextPainter: translationTextPainter,
        ),
      );
    }
    return LyricLayout._internal(
      lineMetrics,
      style,
      viewSize,
      style.calcSelectionAnchorPosition(viewSize.height),
      style.calcActiveAnchorPosition(viewSize.height),
    );
  }
}
