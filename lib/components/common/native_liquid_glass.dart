import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show PlatformViewHitTestBehavior, RenderProxyBox;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/state/settings_glass_state.dart';
import '../../app/theme/app_glass_theme.dart';

/// Android 原生液态玻璃面（QWEA0/Liquid-Glass-Android）。
///
/// 通过 Hybrid Composition 平台视图（[PlatformViewsService.initExpensiveAndroidView]）
/// 嵌入原生组件：
/// - [NativeLiquidGlass]：纯背景玻璃面（[LiquidGlassView]，无子内容），折射
///   /模糊/着色由原生渲染，调用方把 Flutter 内容以 Stack 叠在玻璃之上。
/// - [NativeLiquidGlassTabBar]：框架自带的 iOS 26 底栏 [LiquidGlassTabBar]
///   （玻璃滴选中指示 + 液态拉伸 + 可拖拽），触摸由原生组件消费，切换回调
///   经通道回传 [NativeLiquidGlassTabBar.onSelected]。
///
/// 参数遵循框架 Quick Start 推荐配方：glassColor 默认透明（明暗自适应由
/// 原生 enableAdaptiveTint 完成）、blur 0-200 幂曲线映射 blurAmount（3 = 框架
/// 默认 0.0625，200 = 最强）、thickness 0-200 幂曲线缩放折射/斜面配方（默认
/// 30 = 标准值，200 ≈ 3 倍上限）。
///
/// 仅 Android 可用（[NativeLiquidGlass.supported]）；其他平台沿用
/// liquid_glass_widgets 路径。
class NativeLiquidGlass extends StatefulWidget {
  const NativeLiquidGlass({
    super.key,
    required this.borderRadius,
    this.glassColor = Colors.transparent,
    this.blur = 3,
    this.thickness = 30,
    this.material = 'regular',
  });

  /// 圆角半径（dp；胶囊用高度的一半）。
  final double borderRadius;

  /// 玻璃着色（alpha 即着色强度，0 = 无着色，默认透明走原生明暗自适应）。
  final Color glassColor;

  /// 玻璃模糊强度（0-200，对应 AppGlassSettings.glassBlurStrength）。
  final double blur;

  /// 玻璃折射厚度（0-200，对应 AppGlassSettings.glassThickness）。
  final double thickness;

  /// 材质：`regular`（默认，重可读性）/ `clear`（媒体之上，高透 + 压暗层）。
  final String material;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  @override
  State<NativeLiquidGlass> createState() => _NativeLiquidGlassState();
}

class _NativeLiquidGlassState extends State<NativeLiquidGlass> {
  static const String _viewType = 'feiniu/liquid_glass';

  int? _viewId;

  Map<String, Object> get _params => <String, Object>{
    'cornerRadius': widget.borderRadius,
    'glassColor': widget.glassColor.toARGB32(),
    'blur': widget.blur,
    'thickness': widget.thickness,
    'material': widget.material,
  };

  void _pushUpdate() {
    final id = _viewId;
    if (id == null) return;
    // 参数更新失败静默忽略（视图可能在销毁中）：玻璃参数不随失败升级为异常。
    _LiquidGlassChannel.update(id, _params);
  }

  @override
  void didUpdateWidget(covariant NativeLiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.borderRadius != widget.borderRadius ||
        oldWidget.glassColor != widget.glassColor ||
        oldWidget.blur != widget.blur ||
        oldWidget.thickness != widget.thickness ||
        oldWidget.material != widget.material) {
      // 等本帧构建结束后再下发：避免在构建期间触发平台消息。
      SchedulerBinding.instance.addPostFrameCallback((_) => _pushUpdate());
    }
  }

  @override
  Widget build(BuildContext context) {
    // 玻璃是纯背景层：不参与命中，触摸按原 GlassContainer 行为透传给后面的
    // 页面内容。这同时规避了 Flutter 框架缺陷——PlatformViewSurface
    // （PlatformViewRenderBox）从不初始化 AndroidViewController.pointTransformer，
    // 一旦指针事件被手势仲裁派发给控制器就会抛
    // LateInitializationError: Field 'pointTransformer' has not been initialized。
    return IgnorePointer(
      child: PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (context, controller) => PlatformViewSurface(
          controller: controller,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.translucent,
        ),
        onCreatePlatformView: (params) {
          _viewId = params.id;
          return PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: _viewType,
              layoutDirection:
                  Directionality.maybeOf(context) ?? TextDirection.ltr,
              creationParams: _params,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      ),
    );
  }
}

/// 设置联动的玻璃背景层（卡片/胶囊玻璃化共用）。
///
/// 只渲染玻璃背景（Positioned.fill 占满父级），内容由调用方以 Stack 兄弟层
/// 叠在玻璃之上（与迷你播放器 glassSurface 的分层思路一致，内容重绘不触发
/// 玻璃重新采样）：
/// - Android：[NativeLiquidGlass] 原生玻璃面，模糊/厚度实时跟随
///   [AppGlassSettings.glassBlurStrength] / [AppGlassSettings.glassThickness]。
/// - 其他平台：liquid_glass_widgets 的 [GlassContainer] 通透变体（与迷你
///   播放器同配方）。
///
/// 胶囊/圆形传 `borderRadius: 999` —— 999 也是原生 LiquidGlassView 的默认
/// 哨兵值（全胶囊形状）。
class NativeGlassSurface extends StatelessWidget {
  const NativeGlassSurface({
    super.key,
    required this.borderRadius,
    this.material = 'clear',
  });

  /// 圆角半径（dp；胶囊/圆形用 999 → 全胶囊）。
  final double borderRadius;

  /// 材质：`clear`（iOS 26 "Clear"，高透 + 压暗层，默认）/ `regular`。
  final String material;

  @override
  Widget build(BuildContext context) {
    if (!NativeLiquidGlass.supported) {
      return GlassContainer(
        shape: LiquidRoundedRectangle(borderRadius: borderRadius),
        clipBehavior: Clip.antiAlias,
        settings: kAppGlassSurfaceSettings.copyWith(
          glassColor: const Color(0x1AFFFFFF),
        ),
        useOwnLayer: true,
        quality: GlassQuality.standard,
        child: const SizedBox.expand(),
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: AppGlassSettings.glassBlurStrength,
      builder: (context, blur, _) => ValueListenableBuilder<double>(
        valueListenable: AppGlassSettings.glassThickness,
        builder: (context, thickness, _) => NativeLiquidGlass(
          borderRadius: borderRadius,
          blur: blur,
          thickness: thickness,
          material: material,
        ),
      ),
    );
  }
}

/// 框架自带 iOS 26 底栏 [LiquidGlassTabBar] 的 Flutter 封装。
///
/// 等宽图标+文字标签；选中指示是一颗真实玻璃滴（折射标签行内容），切换时
/// 过冲弹性滑动 + 液态拉伸，且支持手指拖拽。触摸完全由原生组件消费
/// （HC 下 Android 事件分发直达平台视图，不经 Flutter 手势系统），原生切
/// 换后经通道回传 [onSelected]；Dart 侧如需程序化切页，更新 [selectedIndex]
/// 即可（原生带弹性动画）。
class NativeLiquidGlassTabBar extends StatefulWidget {
  const NativeLiquidGlassTabBar({
    super.key,
    required this.titles,
    required this.icons,
    this.selectedIndex = 0,
    this.selectedTint,
    this.onSelected,
    this.blur = 3,
    this.thickness = 30,
    this.material = 'regular',
  });

  /// 各 tab 文字标签（与 [icons] 等长）。
  final List<String> titles;

  /// 各 tab 图标（原生矢量资源名：home/library/music/heart/person）。
  final List<String> icons;

  /// 当前选中下标（Dart → 原生同步）。
  final int selectedIndex;

  /// 选中色（ARGB）；null = 跟随背景明暗自适应白/黑（作者推荐默认）。
  final Color? selectedTint;

  /// 原生点击/拖拽切换后的回调。
  final ValueChanged<int>? onSelected;

  /// 玻璃模糊强度（0-200，对应 AppGlassSettings.glassBlurStrength）。
  final double blur;

  /// 玻璃折射厚度（0-200，对应 AppGlassSettings.glassThickness）。
  final double thickness;

  /// 材质：`regular`（框架默认，自适应染色重可读性）/ `clear`（高透 +
  /// 固定压暗层，最通透）。
  final String material;

  static bool get supported => NativeLiquidGlass.supported;

  @override
  State<NativeLiquidGlassTabBar> createState() =>
      _NativeLiquidGlassTabBarState();
}

class _NativeLiquidGlassTabBarState extends State<NativeLiquidGlassTabBar> {
  static const String _viewType = 'feiniu/liquid_glass_tab_bar';

  int? _viewId;

  Map<String, Object> get _params => <String, Object>{
    'titles': widget.titles,
    'icons': widget.icons,
    'selectedIndex': widget.selectedIndex,
    if (widget.selectedTint != null)
      'selectedTint': widget.selectedTint!.toARGB32(),
    'blur': widget.blur,
    'thickness': widget.thickness,
    'material': widget.material,
  };

  void _handleNativeSelection(int index) {
    if (index != widget.selectedIndex) {
      widget.onSelected?.call(index);
    }
  }

  @override
  void dispose() {
    final id = _viewId;
    if (id != null) {
      _LiquidGlassChannel.unregisterSelection(id);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NativeLiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = _viewId;
    if (id == null) return;
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.selectedTint != widget.selectedTint ||
        oldWidget.blur != widget.blur ||
        oldWidget.thickness != widget.thickness ||
        oldWidget.material != widget.material) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _LiquidGlassChannel.updateTabBar(id, _params);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => _PlatformViewPointTransformer(
        controller: controller,
        // 底栏触摸需要经 Flutter 手势系统仲裁后由控制器下发到原生视图
        // （见 _PlatformViewPointTransformer 注释），因此这里不能包
        // IgnorePointer（与纯背景玻璃相反）。
        child: PlatformViewSurface(
          controller: controller,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.translucent,
        ),
      ),
      onCreatePlatformView: (params) {
        _viewId = params.id;
        _LiquidGlassChannel.registerSelection(
          params.id,
          _handleNativeSelection,
        );
        return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: _viewType,
            layoutDirection:
                Directionality.maybeOf(context) ?? TextDirection.ltr,
            creationParams: _params,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }
}

/// 为平台视图补上 Flutter 框架缺失的 [AndroidViewController.pointTransformer]。
///
/// 框架缺陷：`AndroidViewController.pointTransformer`（全局坐标 → 平台视图
/// 本地坐标）只有 `AndroidView` 组件的 RenderAndroidView 会赋值；
/// [PlatformViewSurface]（PlatformViewRenderBox）从不赋值，任何经手势仲裁
/// 派发给控制器的指针事件都会抛
/// `LateInitializationError: Field 'pointTransformer' has not been
/// initialized`（flutter/flutter#104958），事件也就永远到不了原生视图。
///
/// 本渲染代理盒与 [PlatformViewSurface] 的渲染盒共享同一坐标系（无变换），
/// 构造时用自身 `globalToLocal` 初始化控制器的坐标转换，指针事件即可按
/// RenderAndroidView 同款路径正确下发到原生组件（可交互平台视图必需）。
class _PlatformViewPointTransformer extends SingleChildRenderObjectWidget {
  const _PlatformViewPointTransformer({
    required this.controller,
    required super.child,
  });

  final PlatformViewController controller;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _PointTransformerBox(controller);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _PointTransformerBox renderObject,
  ) {
    renderObject.attachController(controller);
  }
}

class _PointTransformerBox extends RenderProxyBox {
  _PointTransformerBox(PlatformViewController controller) {
    attachController(controller);
  }

  // PlatformViewLink 的 surfaceFactory 只暴露 PlatformViewController，
  // initExpensiveAndroidView 实际返回的 AndroidViewController 才携带
  // pointTransformer 字段，判型后注入即可。
  void attachController(PlatformViewController controller) {
    if (controller is AndroidViewController) {
      controller.pointTransformer = (Offset global) => globalToLocal(global);
    }
  }
}

/// 通道集合：参数更新（Dart → 原生）与底栏切换回调（原生 → Dart，按视图
/// id 路由到对应的 [_NativeLiquidGlassTabBarState]）。
class _LiquidGlassChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.feiniu.music/liquid_glass',
  );

  static final Map<int, void Function(int)> _selectionHandlers = {};
  static bool _handlerInstalled = false;

  static void registerSelection(int viewId, void Function(int) handler) {
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onTabSelected') {
          final args = call.arguments as Map?;
          final id = (args?['id'] as num?)?.toInt();
          final index = (args?['index'] as num?)?.toInt();
          if (id != null && index != null) {
            _selectionHandlers[id]?.call(index);
          }
        }
        return null;
      });
    }
    _selectionHandlers[viewId] = handler;
  }

  static void unregisterSelection(int viewId) {
    _selectionHandlers.remove(viewId);
  }

  static Future<void> update(int viewId, Map<String, Object> params) async {
    try {
      await _channel.invokeMethod<dynamic>('update', {'id': viewId, ...params});
    } on PlatformException {
      // 视图可能已在销毁中：玻璃参数更新失败无需升级为异常。
    }
  }

  static Future<void> updateTabBar(
    int viewId,
    Map<String, Object> params,
  ) async {
    try {
      await _channel.invokeMethod<dynamic>('update', {'id': viewId, ...params});
    } on PlatformException {
      // 同上，静默忽略。
    }
  }
}
