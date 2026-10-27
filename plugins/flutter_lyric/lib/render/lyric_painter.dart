import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';

const _debugLyric = false;

class LyricPainter extends CustomPainter {
  final LyricLayout layout;
  final int playIndex;
  final double scrollY;
  final double activeHighlightWidth;
  final LyricLineSwitchState switchState;
  final bool isSelecting;
  final bool showSelectionShadow;
  final LyricStyle style;
  final Function(
    int,
  ) onAnchorIndexChange;
  final Function(
    Map<int, Rect>,
  ) onShowLineRectsChange;

  LyricPainter({
    required this.layout,
    required this.playIndex,
    required this.scrollY,
    required this.onAnchorIndexChange,
    required this.activeHighlightWidth,
    required this.switchState,
    required this.isSelecting,
    required this.showSelectionShadow,
    required this.onShowLineRectsChange,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    //溢出裁剪
    if (!_debugLyric) {
      canvas.clipRect(Rect.fromLTRB(-layout.style.contentPadding.left, 0,
          size.width + layout.style.contentPadding.right, size.height));
    }

    final selectionPosition = layout.selectionAnchorPosition;
    final activePosition = layout.activeAnchorPosition;
    if (_debugLyric) {
      canvas.drawLine(
        Offset(0, selectionPosition),
        Offset(size.width, selectionPosition),
        Paint()..color = layout.style.selectedColor,
      );
      canvas.drawLine(
        Offset(0, activePosition),
        Offset(size.width, activePosition),
        Paint()..color = layout.style.selectedColor,
      );
    }
    var totalTranslateY = 0.0;
    canvas.translate(0, -scrollY);
    totalTranslateY -= scrollY;
    var selectedIndex = -1;
    final showLineRects = <int, Rect>{};
    for (var i = 0; i < layout.metrics.length; i++) {
      final isActive = i == playIndex;
      final lineHeight = layout.getLineHeight(isActive, i);
      totalTranslateY += lineHeight;
      //计算高亮
      if ((totalTranslateY + layout.style.lineGap / 2) >= selectionPosition &&
          selectedIndex == -1) {
        selectedIndex = i;
        onAnchorIndexChange(
          i,
        );
      }
      if (totalTranslateY - lineHeight >= size.height) {
        break;
      }
      if (totalTranslateY > 0) {
        final lineRect = Rect.fromLTWH(0, totalTranslateY - lineHeight,
            size.width + layout.style.contentPadding.horizontal, lineHeight);
        showLineRects[i] = lineRect;
        if (style.activeLineOnly && !isActive) {
        } else {
          drawLine(
            canvas,
            layout.metrics[i],
            size,
            i,
            selectedIndex == i,
          );
        }
      }
      totalTranslateY += layout.style.lineGap;
      if (_debugLyric) {
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, lineHeight),
            Paint()..color = Colors.purple.withAlpha(50));
      }
      canvas.translate(0, lineHeight + layout.style.lineGap);
    }
    onShowLineRectsChange(showLineRects);
  }

  drawHighlight(
    Canvas canvas,
    Size size,
    List<ui.LineMetrics> metrics, {
    double highlightTotalWidth = 0,
  }) {
    if (highlightTotalWidth < 0) return;
    final activeHighlightColor = layout.style.activeHighlightColor;
    final activeHighlightGradient = layout.style.activeHighlightGradient;
    if (activeHighlightColor == null && activeHighlightGradient == null) {
      return;
    }

    final highlightFullMode = highlightTotalWidth == double.infinity;
    var accWidth = 0.0;

    final Paint paint = Paint()..blendMode = BlendMode.srcIn;

    for (var line in metrics) {
      double lineDrawWidth;
      bool isFullLine;

      if (highlightFullMode) {
        isFullLine = true;
        lineDrawWidth = line.width;
      } else {
        final remain = highlightTotalWidth - accWidth;
        if (remain <= 0) break;

        lineDrawWidth = remain < line.width ? remain : line.width;
        isFullLine = remain >= line.width;
      }

      final top = line.baseline - line.ascent;
      final height = (line.ascent + line.descent);

      final extraFadeWidth = style.activeHighlightExtraFadeWidth;
      final pad = 2;
      final rect = Rect.fromLTWH(
        line.left - pad,
        top,
        lineDrawWidth + pad,
        height,
      );

      final grad = style.activeHighlightGradient ??
          LinearGradient(colors: [activeHighlightColor!, activeHighlightColor]);
      handleExtraFadeWidth() {
        if (extraFadeWidth <= 0) return 0;
        paint.shader = LinearGradient(colors: [
          grad.colors.last,
          style.activeStyle.color ?? grad.colors.last
        ]).createShader(Rect.fromLTWH(
            rect.left + rect.width, rect.top, extraFadeWidth, rect.height));
        canvas.drawRect(
            Rect.fromLTWH(
                rect.left + rect.width, rect.top, extraFadeWidth, rect.height),
            paint);
      }

      handleExtraFadeWidth();
      paint.shader = grad.createShader(
          Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height));
      canvas.drawRect(rect, paint);
      accWidth += line.width;

      if (!isFullLine) break;
    }
  }

  double handleSwitchAnimation(
    Canvas canvas,
    LineMetrics metric,
    int index,
    LyricLineSwitchState switchState,
    TextPainter painter,
    Size size,
  ) {
    if (layout.style.enableSwitchAnimation != true) return 0;
    double calcTranslateX(double contentWidth) {
      var transX = 0.0;
      if (layout.style.contentAlignment == CrossAxisAlignment.center) {
        transX = contentWidth / 2;
      } else if (layout.style.contentAlignment == CrossAxisAlignment.end) {
        transX = contentWidth;
      }
      return transX;
    }

    final transX = calcTranslateX(painter.width);
    if (index == switchState.enterIndex) {
      final enterAnimationValue = switchState.enterAnimationValue;
      final fromHeight = metric.height;
      final toHeight = metric.activeHeight;
      final transY = toHeight;
      canvas.translate(transX, transY);
      canvas.scale(
          1 - ((toHeight - fromHeight) / toHeight) * (1 - enterAnimationValue));
      canvas.translate(-transX, -transY);
    }
    // EXIT
    if (index == switchState.exitIndex) {
      final exitAnimationValue = switchState.exitAnimationValue;
      final fromHeight = metric.activeHeight;
      final toHeight = metric.height;
      final transY = 0.0;
      canvas.translate(transX, transY);
      final scale =
          ((fromHeight - toHeight) / fromHeight) * (1 - exitAnimationValue);
      canvas.scale(1 + scale);
      canvas.translate(-transX, -transY);
      return toHeight * scale;
    }
    return 0;
  }

  drawLine(
    Canvas canvas,
    LineMetrics metric,
    Size size,
    int index,
    bool isInAnchorArea,
  ) {
    final isActive = playIndex == index;
    final selected = isSelecting && isInAnchorArea;
    final basePainter = isActive ? metric.activeTextPainter : metric.textPainter;
    final baseSpan = basePainter.text;
    final baseStyle = (baseSpan is TextSpan) ? baseSpan.style : null;
    final selectionPainter = selected && baseStyle != null
        ? (TextPainter(
            text: TextSpan(
              text: basePainter.text?.toPlainText(),
              style: baseStyle.copyWith(
                color: layout.style.selectedColor,
              ),
            ),
            textAlign: basePainter.textAlign,
            textDirection: basePainter.textDirection ?? TextDirection.ltr,
            maxLines: basePainter.maxLines,
            ellipsis: basePainter.ellipsis,
            locale: basePainter.locale,
            strutStyle: basePainter.strutStyle,
            textWidthBasis: basePainter.textWidthBasis,
            textHeightBehavior: basePainter.textHeightBehavior,
          )..layout(maxWidth: size.width))
        : null;
    final painter = selectionPainter ?? basePainter;

    // ===== 远端虚化（参考 APK：越远离当前播放行越模糊、越淡）=====
    // 模糊只作用于「文字内容」（saveLayer + ImageFilter），绝不采样背景：
    // 背景采样(BackdropFilter)会把页面底色一起模糊、再以不透明方式重绘回
    // 该区域，亮色文字被涂抹进底色 → 观感即「字体发白、蒙一层白雾」。
    // 逐行渐隐通过重建带 alpha 的 TextPainter 实现（布局内按行缓存）。
    final defocusT = _defocusFactor(index);
    final defocusSigma = defocusT * style.defocusSigma;
    final defocusOpacity = 1 - defocusT * (1 - style.defocusMinOpacity);
    final useDefocus = defocusSigma > 0.01 && !selected;

    final mainPainter = defocusOpacity < 0.999
        ? (layout.defocusPainter(
              index: index,
              playIndex: playIndex,
              isActive: isActive,
              isTranslation: false,
              opacity: defocusOpacity,
            ) ??
            painter)
        : painter;

    final mainHeight = isActive ? metric.activeHeight : metric.height;
    if (useDefocus) {
      // 图层范围要盖住模糊扩散的范围，否则模糊会被图层边界裁掉；留足余量
      // 也避免把选中框（左右各 12px、上下各 8px + 投影）裁出缺口。
      final pad = 3.0 * defocusSigma + 16.0;
      canvas.saveLayer(
        Rect.fromLTWH(
          -pad,
          -pad,
          size.width + 2 * pad,
          mainHeight +
              layout.style.translationLineGap +
              metric.translationHeight +
              2 * pad,
        ),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: defocusSigma,
            sigmaY: defocusSigma,
          ),
      );
    }
    canvas.save();
    canvas.translate(calcContentAliginOffset(painter.width, size.width), 0);
    if (_debugLyric) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, painter.width, painter.height),
        Paint()
          ..color = !isActive
              ? Colors.blue.withAlpha(50)
              : Colors.red.withAlpha(50));
    }
    final switchOffset = handleSwitchAnimation(
        canvas, metric, index, switchState, painter, size);
    if (selected && !_debugLyric) {
      final lineHeight = layout.getLineHeight(isActive, index);
      final bgPadX = 12.0;
      final bgPadY = 8.0;
      final bgWidth = (metric.translationWidth > painter.width)
          ? metric.translationWidth
          : painter.width;
      final rect = Rect.fromLTWH(
        -bgPadX,
        -bgPadY,
        bgWidth + bgPadX * 2,
        lineHeight + bgPadY * 2,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      final path = Path()..addRRect(rrect);
      // 拖动过程中也要保留「当前歌词的选中框」（填充），否则拖动时当前行
      // 完全没有视觉锚点；只有投影（阴影）等拖动停稳后再淡入。
      if (showSelectionShadow) {
        canvas.drawShadow(
          path,
          const Color(0xFF000000).withValues(alpha: 0.25),
          10,
          false,
        );
      }
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = layout.style.selectedColor.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill,
      );
    }

    // 参考 APK 技术路线：行内容严格「单遍绘制」。
    // 旧实现在层外先画一遍文字，进入 saveLayer 后又画一遍再由 drawHighlight
    // 用 srcIn 上色——两次绘制让抗锯齿边缘 alpha 双重累积（0.5+0.5→~0.75），
    // 笔画外扩、发胖发白，观感如蒙一层白雾，也是当前行「发白」的根因。
    // 现在只在需要高亮时进 saveLayer、层内画一次，srcIn 按这一次的文字 alpha
    // 上色；无高亮时层外画一次。全程文字只被绘制一次。
    final hasHighlightPaint =
        layout.style.activeHighlightColor != null ||
        layout.style.activeHighlightGradient != null;
    final needHighlight = hasHighlightPaint &&
        (isActive ||
            (index == switchState.exitIndex &&
                switchState.exitAnimationValue < 1 &&
                style.enableSwitchAnimation));
    if (needHighlight) {
      canvas.saveLayer(
        Rect.fromLTWH(
          -layout.style.contentPadding.left,
          -4,
          size.width + layout.style.contentPadding.horizontal,
          mainHeight + 8,
        ),
        Paint(),
      );
      try {
        mainPainter.paint(canvas, Offset.zero);
      } catch (_) {}
      if (isActive) {
        drawHighlight(
          canvas,
          size,
          metric.activeMetrics,
          highlightTotalWidth: activeHighlightWidth,
        );
      } else {
        drawHighlight(
          canvas,
          size,
          metric.metrics,
          highlightTotalWidth: double.infinity,
        );
      }
      canvas.restore();
    } else {
      try {
        mainPainter.paint(canvas, Offset.zero);
      } catch (_) {}
    }
    canvas.restore();
    if (metric.line.translation?.isNotEmpty == true) {
      final tBasePainter = metric.translationTextPainter;
      final tBaseSpan = tBasePainter.text;
      final tBaseStyle = (tBaseSpan is TextSpan) ? tBaseSpan.style : null;
      final tSelectionPainter = selected && tBaseStyle != null
          ? (TextPainter(
              text: TextSpan(
                text: metric.line.translation,
                style: tBaseStyle.copyWith(
                  color: layout.style.selectedTranslationColor,
                ),
              ),
              textAlign: tBasePainter.textAlign,
              textDirection: tBasePainter.textDirection ?? TextDirection.ltr,
              maxLines: tBasePainter.maxLines,
              ellipsis: tBasePainter.ellipsis,
              locale: tBasePainter.locale,
              strutStyle: tBasePainter.strutStyle,
              textWidthBasis: tBasePainter.textWidthBasis,
              textHeightBehavior: tBasePainter.textHeightBehavior,
            )..layout(maxWidth: size.width))
          : null;
      final tActivePainter = (!selected && isActive && tBaseStyle != null)
          ? (TextPainter(
              text: TextSpan(
                text: metric.line.translation,
                style: tBaseStyle.copyWith(color: layout.style.translationActiveColor),
              ),
              textAlign: tBasePainter.textAlign,
              textDirection: tBasePainter.textDirection ?? TextDirection.ltr,
              maxLines: tBasePainter.maxLines,
              ellipsis: tBasePainter.ellipsis,
              locale: tBasePainter.locale,
              strutStyle: tBasePainter.strutStyle,
              textWidthBasis: tBasePainter.textWidthBasis,
              textHeightBehavior: tBasePainter.textHeightBehavior,
            )..layout(maxWidth: size.width))
          : null;
      final tPainter = tSelectionPainter ??
          tActivePainter ??
          (defocusOpacity < 0.999
              ? (layout.defocusPainter(
                    index: index,
                    playIndex: playIndex,
                    isActive: isActive,
                    isTranslation: true,
                    opacity: defocusOpacity,
                  ) ??
                  tBasePainter)
              : tBasePainter);
      canvas.save();
      canvas.translate(calcContentAliginOffset(tPainter.width, size.width), 0);
      canvas.translate(0, switchOffset);
      try {
        tPainter.paint(
          canvas,
          Offset(0, mainHeight + layout.style.translationLineGap),
        );
      } catch (_) {
        // 避免系统字体变更触发 assert(debugSize == size);
      }
      canvas.translate(0, -switchOffset);
      canvas.restore();
    }
    if (useDefocus) {
      canvas.restore();
    }
  }

  /// 远端虚化系数：按与当前播放行的「行距」归一化到 0~1。
  /// 0 = 不虚化（当前行及其近邻），1 = 达到最大虚化。
  double _defocusFactor(int index) {
    final s = style;
    if (s.defocusSigma <= 0) return 0;
    // 换行动画中的两行正在做位移/缩放，图层边界会裁切它们，暂不虚化。
    if (index == switchState.enterIndex || index == switchState.exitIndex) {
      return 0;
    }
    final distance = (index - playIndex).abs().toDouble();
    final start = s.defocusStartDistance;
    final end = s.defocusEndDistance > start ? s.defocusEndDistance : start + 1;
    if (distance <= start) return 0;
    return ((distance - start) / (end - start)).clamp(0.0, 1.0);
  }

  double calcContentAliginOffset(double contentWidth, double containerWidth) {
    switch (layout.style.contentAlignment) {
      case CrossAxisAlignment.start:
        return 0;
      case CrossAxisAlignment.end:
        return containerWidth - contentWidth;
      case CrossAxisAlignment.center:
        return (containerWidth - contentWidth) / 2;
      default:
        return 0;
    }
  }

  @override
  bool shouldRepaint(covariant LyricPainter oldDelegate) {
    return layout != oldDelegate.layout ||
        playIndex != oldDelegate.playIndex ||
        scrollY != oldDelegate.scrollY ||
        activeHighlightWidth != oldDelegate.activeHighlightWidth ||
        switchState != oldDelegate.switchState ||
        isSelecting != oldDelegate.isSelecting ||
        showSelectionShadow != oldDelegate.showSelectionShadow ||
        style != oldDelegate.style;
  }
}
