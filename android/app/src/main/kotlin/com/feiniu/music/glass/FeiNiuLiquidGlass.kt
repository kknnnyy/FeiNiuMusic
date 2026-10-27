package com.feiniu.music.glass

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.drawable.Drawable
import android.view.View
import android.view.ViewGroup
import com.example.liquidglass.GlassMaterial
import com.example.liquidglass.LiquidGlassView
import com.feiniu.music.R
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.pow

/**
 * 原生液态玻璃接入（QWEA0/Liquid-Glass-Android，com.github.QWEA0:liquidglass）。
 *
 * Android 平台把 liquid_glass_widgets 的玻璃面替换为本框架：
 * - `feiniu/liquid_glass`：纯背景玻璃面（[LiquidGlassView]，无子 View），
 *   Flutter 内容由 Dart 侧以 Stack 叠在玻璃上（迷你播放器 / 播放页底面板）。
 * - `feiniu/liquid_glass_tab_bar`：框架自带的 iOS 26 底栏组件
 *   [LiquidGlassTabBar]（玻璃滴选中指示、液态拉伸、可拖拽），触摸由原生
 *   组件自己消费，切换回调经通道回传 Dart。
 *
 * 两种视图都通过 Hybrid Composition（Dart 侧 initExpensiveAndroidView）嵌入。
 * 背景折射关键：backdropSource 必须显式指向 FlutterView —— HC 模式下平台
 * 视图之后的 Flutter 场景由 FlutterImageView（真实 Android View）绘制，可被
 * 本框架的 RenderNode/View 树采集捕获；默认的「直接父视图」是平台视图包装
 * 容器，采不到 Flutter 内容。
 *
 * 参数遵循框架 Quick Start 推荐配方（见 README）：
 * glassTint 默认透明（iOS 观感由 enableAdaptiveTint 按背景明暗自动调节）、
 * refractionHeight=12dp / bevelWidth=24dp（宽扁胶囊的作者推荐值，
 * adaptiveLensScale 会按短边自适应）、dispersionStrength=0.12、
 * enableSensorHighlight=true、enableDynamicBackground=true（背景移动时
 * 必开，否则背景被冻结——README 标注的头号集成错误）。
 */
object FeiNiuLiquidGlass {
    private const val CHANNEL = "com.feiniu.music/liquid_glass"

    /** 仅主线程访问（PlatformView 创建/销毁与 MethodChannel 均在主线程回调）。 */
    private val views = mutableMapOf<Int, GlassViewHandle>()
    private lateinit var channel: MethodChannel

    fun setup(engine: FlutterEngine, messenger: BinaryMessenger) {
        val registry = engine.platformViewsController.registry
        registry.registerViewFactory("feiniu/liquid_glass", LiquidGlassViewFactory())
        registry.registerViewFactory("feiniu/liquid_glass_tab_bar", LiquidGlassTabBarViewFactory())
        channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val view = views[(call.argument<Number>("id"))?.toInt()]
                    if (view != null && call.arguments is Map<*, *>) {
                        view.handleUpdate(call.arguments as Map<*, *>)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun register(viewId: Int, view: GlassViewHandle) {
        views[viewId] = view
    }

    fun unregister(viewId: Int) {
        views.remove(viewId)
    }

    /**
     * 采集背景期间隐藏所有玻璃平台视图（含采集发起者自身）：保证采到纯
     * Flutter 内容、避免把效果层画进采集内容形成反馈回路。
     * 仅主线程调用（View 绘制回调都在主线程）。
     */
    fun <T> withGlassViewsHidden(block: () -> T): T {
        val hidden = views.values
            .mapNotNull { (it as? PlatformView)?.getView() }
            .filter { it.isShown }
        hidden.forEach { it.visibility = View.INVISIBLE }
        return try {
            block()
        } finally {
            hidden.forEach { it.visibility = View.VISIBLE }
        }
    }

    /** 原生组件 → Dart 回调（底栏切换）。 */
    fun notifyTabSelected(viewId: Int, index: Int) {
        if (::channel.isInitialized) {
            channel.invokeMethod(
                "onTabSelected",
                mapOf("id" to viewId, "index" to index),
            )
        }
    }
}

/** 平台视图在注册表中的统一句柄：接收 Dart 侧的参数更新。 */
interface GlassViewHandle {
    fun handleUpdate(params: Map<*, *>)
}

/** 底栏图标名 → 应用内置矢量资源（避免反射 getIdentifier）。 */
private fun tabIcon(context: Context, name: String?): Drawable? = when (name) {
    "home" -> context.getDrawable(R.drawable.ic_tab_home)
    "library" -> context.getDrawable(R.drawable.ic_tab_library)
    "music" -> context.getDrawable(R.drawable.ic_tab_music)
    "heart" -> context.getDrawable(R.drawable.ic_tab_heart)
    "person" -> context.getDrawable(R.drawable.ic_tab_person)
    else -> null
}

class LiquidGlassViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return LiquidGlassPlatformView(context, viewId, args as? Map<*, *>)
    }
}

class LiquidGlassTabBarViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return LiquidGlassTabBarPlatformView(context, viewId, args as? Map<*, *>)
    }
}

/**
 * 纯背景玻璃面：只渲染背景（折射/模糊/着色），自身无子内容，触摸透传给
 * 上层 Flutter 内容（原生视图不可点击；Dart 侧再包 IgnorePointer 双保险）。
 */
class LiquidGlassPlatformView(
    context: Context,
    private val viewId: Int,
    params: Map<*, *>?,
) : PlatformView, GlassViewHandle {
    private val glass = LiquidGlassView(context)

    init {
        glass.isClickable = false
        glass.isLongClickable = false
        glass.isFocusable = false
        glass.enablePressEffect = false
        findFlutterView(context)?.let { glass.backdropSource = it }
        applyGlassParams(glass, params ?: emptyMap<Any, Any>(), context.resources.displayMetrics.density)
        FeiNiuLiquidGlass.register(viewId, this)
    }

    override fun getView(): View = glass

    override fun handleUpdate(params: Map<*, *>) {
        applyGlassParams(glass, params, glass.resources.displayMetrics.density)
        glass.invalidate()
    }

    override fun dispose() {
        glass.backdropSource = null
        FeiNiuLiquidGlass.unregister(viewId)
    }
}

/**
 * 框架自带 iOS 26 底栏：玻璃滴选中指示 + 液态拉伸 + 可拖拽。触摸由原生
 * 组件消费（HC 下 Android 事件分发直达真实 View，不经过 Flutter 手势系统），
 * 切换结果经 [FeiNiuLiquidGlass.notifyTabSelected] 回传 Dart。
 */
class LiquidGlassTabBarPlatformView(
    context: Context,
    private val viewId: Int,
    params: Map<*, *>?,
) : PlatformView, GlassViewHandle {
    // 增强版底栏（FeiNiuGlassTabBar）：切换时玻璃滴放大脉冲（比导航栏还宽），
    // 其余行为与框架 LiquidGlassTabBar 一致。
    private val bar = FeiNiuGlassTabBar(context)
    private val density = context.resources.displayMetrics.density

    init {
        findFlutterView(context)?.let { bar.backdropSource = it }
        // 玻璃参数（材质/模糊/折射）与背景玻璃面同一套配方；不传 cornerRadius，
        // 保持框架默认的全胶囊形状。applyGlassParams 已含 enableDynamicBackground。
        applyGlassParams(bar, params ?: emptyMap<Any, Any>(), density)
        val titles = (params?.get("titles") as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        val icons = (params?.get("icons") as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        bar.setTabs(
            titles.mapIndexed { i, title ->
                FeiNiuGlassTabBar.TabItem(title, tabIcon(context, icons.getOrNull(i)))
            },
        )
        (params?.get("selectedIndex") as? Number)?.toInt()?.let {
            if (it in 1 until titles.size) bar.selectedIndex = it
        }
        // null = 跟随背景明暗自适应白/黑（作者推荐，iOS 观感）
        (params?.get("selectedTint") as? Number)?.toLong()?.toInt()?.let {
            bar.selectedTintColor = it
        }
        bar.onTabSelected = { index -> FeiNiuLiquidGlass.notifyTabSelected(viewId, index) }
        FeiNiuLiquidGlass.register(viewId, this)
    }

    override fun getView(): View = bar

    override fun handleUpdate(params: Map<*, *>) {
        applyGlassParams(bar, params, density)
        bar.invalidate()
        (params["selectedIndex"] as? Number)?.toInt()?.let {
            if (it != bar.selectedIndex) bar.selectedIndex = it
        }
        (params["selectedTint"] as? Number)?.toLong()?.toInt()?.let {
            bar.selectedTintColor = it
        }
    }

    override fun dispose() {
        bar.backdropSource = null
        bar.onTabSelected = null
        FeiNiuLiquidGlass.unregister(viewId)
    }
}

/**
 * Dart 侧参数（dp / 语义值）映射为框架物理像素参数，按 Quick Start 配方。
 *
 * - blur 0-200（Dart 语义）→ blurAmount 0-1 分数：框架计算
 *   blurRadius = 4 + blurAmount * 32（px）。幂曲线 (blur/200)^0.66 使默认
 *   3 → 0.0625（框架默认浅模糊）手感不变，同时把 0-200 全程展开到 0-1
 *   （旧线性映射 16 就到旧上限，200 无从加大）。
 * - thickness 0-200（Dart 折射深度）→ 折射/斜面按 Quick Start 宽扁胶囊推荐
 *   （refractionHeight=12dp、bevelWidth=24dp）幂曲线缩放：默认 30 = 标准配方
 *   （scale 1.0），200 ≈ 3 倍上限。
 * - glassColor 默认透明：iOS 观感的明暗自适应由 enableAdaptiveTint 完成。
 */
internal fun applyGlassParams(view: LiquidGlassView, params: Map<*, *>, density: Float) {
    // 仅在显式传入时设置：LiquidGlassTabBar 等自带形状的组件保持框架默认
    // （LiquidGlassView.cornerRadius 默认 999f = 全胶囊），不传即不覆盖。
    (params["cornerRadius"] as? Number)?.toDouble()?.let { cornerRadiusDp ->
        view.cornerRadius = (cornerRadiusDp * density).toFloat().coerceAtLeast(0f)
    }

    val glassColor = (params["glassColor"] as? Number)?.toLong()?.toInt()
        ?: android.graphics.Color.TRANSPARENT
    view.glassTint = glassColor

    // REGULAR（框架默认，自适应染色重可读性）/ CLEAR（高透 + 固定压暗层，
    // iOS 26 "Clear" 材质，覆盖媒体之上最通透）。
    view.material =
        if (params["material"] == "clear") GlassMaterial.CLEAR else GlassMaterial.REGULAR

    val blur = ((params["blur"] as? Number)?.toDouble() ?: 3.0).coerceIn(0.0, 200.0)
    view.blurAmount = ((blur / 200.0).coerceIn(0.0, 1.0)).pow(0.66).toFloat().coerceIn(0f, 1f)

    val thickness = ((params["thickness"] as? Number)?.toDouble() ?: 30.0).coerceIn(0.0, 200.0)
    val scale = (thickness / 30.0).pow(0.58).toFloat().coerceAtMost(3f)
    view.refractionHeight = (12f * density) * scale
    view.bevelWidth = ((24f * density) * scale).coerceAtLeast(2f)
    view.dispersionStrength = 0.12f
    view.enableSensorHighlight = true
    // 注意：enableAdaptiveTint/enableDynamicBackground 不能关闭——实测关闭后
    // libhwui computeClipAndTransformImpl 无限递归栈溢出闪退，必须保持 true。
    view.enableAdaptiveTint = true
    view.enableDynamicBackground = true
}

/** 从平台视图的 context（Activity 或其包装）出发，向上找到窗口再向下找 FlutterView。 */
internal fun findFlutterView(context: Context): FlutterView? {
    var ctx: Context = context
    while (ctx is ContextWrapper) {
        if (ctx is Activity) {
            val decor = ctx.window?.decorView ?: return null
            return findFlutterViewInChildren(decor)
        }
        ctx = ctx.baseContext
    }
    return null
}

internal fun findFlutterViewInChildren(view: View): FlutterView? {
    if (view is FlutterView) return view
    if (view is ViewGroup) {
        for (i in 0 until view.childCount) {
            findFlutterViewInChildren(view.getChildAt(i))?.let { return it }
        }
    }
    return null
}
