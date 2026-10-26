/**
 * 飞牛音乐定制的液态玻璃底栏：基于框架 [LiquidGlassTabBar] 的增强版。
 *
 * 与框架原版的差异在切换动画（[animateDropletTo]）：
 * - 原版：玻璃滴过冲滑动 + 上限 22% 的液态拉伸，滴被钳制在标签行内。
 * - 增强：切换时玻璃滴像**放大镜**一样横纵等比放大（峰值约 1.45 倍，以导航栏
 *   垂直中线为放大中心），随滑动透出下方内容，再收缩落位。
 *
 * 平台视图（HC 包装容器）会把内容裁剪在自己的边界内，滴放大后会超出边界，
 * 必须画在平台视图之外：脉冲期间把栏内的滴藏起，在窗口 DecorView 上挂一颗同样式
 * 的独立玻璃滴执行放大动画——它折射整个窗口的真实像素，出界区域不会黑；
 * 动画结束移除并恢复栏内的滴。拿不到 decor 时退回栏内脉冲（出界部分
 * 靠把 backdropSource 临时切到 FlutterView 保证不黑）。
 *
 * 其余行为（点击/拖拽/样式/明暗自适应）与框架原版一致。
 */
package com.feiniu.music.glass

import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.example.liquidglass.LiquidGlassView
import kotlin.math.abs

class FeiNiuGlassTabBar(context: Context) : LiquidGlassView(context) {

    /** 一个标签：标题 + 可选图标（icon 为 null 时该标签退化为纯文字样式） */
    class TabItem(val title: CharSequence, val icon: Drawable? = null)

    /** 标签切换回调（点击、拖拽吸附或代码设置 [selectedIndex] 都会触发） */
    var onTabSelected: ((index: Int) -> Unit)? = null

    /** 选中项着色（默认 null = 跟随背景明暗用白/黑） */
    var selectedTintColor: Int? = null
        set(value) {
            if (field != value) {
                field = value
                updateTabStyles()
            }
        }

    private var selected = 0

    /** 当前选中标签下标；设置时玻璃滴滑过去并触发 [onTabSelected] */
    var selectedIndex: Int
        get() = selected
        set(value) = selectTab(value, animate = true)

    private class TabHolder(val root: LinearLayout, val icon: ImageView?, val label: TextView)

    private val tabsRow = LinearLayout(context)
    private val tabs = mutableListOf<TabHolder>()

    /** 玻璃滴指示：真玻璃，平时折射 bar 内容，放大脉冲期间折射页面内容 */
    private val droplet = LiquidGlassView(context)

    /** 放大脉冲期间的折射源：FlutterView（出界区域采页面内容，不渲染黑底） */
    private val flutterBackdrop = findFlutterView(context)

    private var overLightAppearance = false

    // 触摸状态（整条 bar 统一处理：点击选择 + 拖拽玻璃滴）
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var downX = 0f
    private var dragging = false
    private var settleAnimator: ValueAnimator? = null

    /** 放大脉冲期间挂在 DecorView 上的独立玻璃滴（动画结束即移除） */
    private var pulseOverlay: LiquidGlassView? = null

    private companion object {
        private const val TAG = "FeiNiuGlassTabBar"
    }

    init {
        // 标签/拖拽自己处理，整条 bar 的按压缩放反而突兀
        enablePressEffect = false
        // 放大脉冲的玻璃滴会超出 bar 边界，自己这层先解除裁剪
        clipChildren = false
        clipToPadding = false

        val pad = dp(4)
        setPadding(pad, pad, pad, pad)

        tabsRow.orientation = LinearLayout.HORIZONTAL
        // 垂直居中：标签行中线 = 栏中线，玻璃滴/放大脉冲的聚焦中心随之对齐
        addView(
            tabsRow,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL),
        )

        droplet.apply {
            enablePressEffect = false
            // 玻璃滴内图标保持清晰：只折射不模糊（iOS 的滴是清透的放大镜）
            enableBackdropBlur = false
            cornerRadius = 999f
            // iOS 的滴内部平坦、只在边缘轻微弯折——斜面窄、折射浅
            bevelWidth = dpF(8)
            refractionHeight = dpF(4)
            dispersionStrength = 0.04f
            visibility = GONE
        }
        // 玻璃滴叠在标签行上方，折射行内容——必须后 add（先绘制行，再绘制滴）。
        // 背景保持默认的直接父容器（= bar 自身）；放大脉冲期间才切 FlutterView。
        addView(droplet, LayoutParams(0, 0, Gravity.TOP or Gravity.START))

        overLightAppearance = isOverLightBackground
    }

    /** 重建标签列表（图标 + 标题），选中项重置为第 0 个（不触发回调） */
    fun setTabs(items: List<TabItem>) {
        tabsRow.removeAllViews()
        tabs.clear()

        items.forEach { item ->
            val root = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
            }
            var icon: ImageView? = null
            val label: TextView
            if (item.icon != null) {
                // iOS 布局：26dp 图标在上，10sp 小字在下
                root.setPadding(dp(2), dp(7), dp(2), dp(7))
                icon = ImageView(context).apply { setImageDrawable(item.icon) }
                root.addView(icon, LinearLayout.LayoutParams(dp(26), dp(26)))
                label = TextView(context).apply {
                    text = item.title
                    textSize = 10f
                    maxLines = 1
                    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                }
                root.addView(
                    label,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply { topMargin = dp(2) }
                )
            } else {
                // 纯文字标签
                root.setPadding(dp(4), dp(12), dp(4), dp(12))
                label = TextView(context).apply {
                    text = item.title
                    textSize = 14f
                    maxLines = 1
                    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                }
                root.addView(label)
            }
            tabs += TabHolder(root, icon, label)
            tabsRow.addView(root, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }

        // 直接改内部状态：初始化不算切换，不触发回调
        selected = 0
        updateTabStyles()
        droplet.visibility = if (tabs.isEmpty()) GONE else VISIBLE
        requestLayout()
    }

    // ==================== 选择与样式 ====================

    private fun selectTab(index: Int, animate: Boolean) {
        val clamped = index.coerceIn(0, (tabs.size - 1).coerceAtLeast(0))
        val changed = clamped != selected
        selected = clamped
        if (changed) updateTabStyles()
        if (animate) animateDropletTo(clamped) else syncDroplet()
        if (changed) onTabSelected?.invoke(clamped)
    }

    private fun updateTabStyles() {
        val selectedColor = selectedTintColor
            ?: if (overLightAppearance) 0xE6000000.toInt() else 0xFFFFFFFF.toInt()
        val normalColor = if (overLightAppearance) 0x8C000000.toInt() else 0xB8FFFFFF.toInt()

        tabs.forEachIndexed { index, tab ->
            val color = if (index == selected) selectedColor else normalColor
            tab.icon?.imageTintList = ColorStateList.valueOf(color)
            tab.label.setTextColor(color)
        }
        // 玻璃滴折射的是行内容的截图，配色变了要重採一帧
        droplet.invalidate()
    }

    override fun onAppearanceChanged(isOverLight: Boolean) {
        overLightAppearance = isOverLight
        droplet.overLight = isOverLight
        updateTabStyles()
    }

    // ==================== 玻璃滴定位与动画 ====================

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        // 布局完成后标签宽度才可用；动画/拖拽中不要打断当前位置
        if (settleAnimator?.isRunning != true && !dragging) syncDroplet()
    }

    override fun onDetachedFromWindow() {
        // 平台视图销毁时若脉冲还在跑，cancel 会触发 onAnimationEnd 清掉 decor 滴
        settleAnimator?.cancel()
        super.onDetachedFromWindow()
    }

    /** 玻璃滴无动画对齐到选中标签（尺寸随标签，位置用 translation 驱动） */
    private fun syncDroplet() {
        val tab = tabs.getOrNull(selected)?.root
        if (tab == null || tab.width <= 0) {
            droplet.visibility = GONE
            return
        }
        droplet.visibility = VISIBLE
        syncDropletSize(tab.width, tab.height)
        droplet.translationX = (tabsRow.left + tab.left - paddingLeft).toFloat()
        droplet.translationY = (tabsRow.top + tab.top - paddingTop).toFloat()
        droplet.scaleX = 1f
        droplet.scaleY = 1f
        droplet.invalidate()
    }

    private fun syncDropletSize(w: Int, h: Int) {
        val lp = droplet.layoutParams as LayoutParams
        if (lp.width != w || lp.height != h) {
            lp.width = w
            lp.height = h
            droplet.layoutParams = lp
        }
    }

    /**
     * 玻璃滴滑到指定标签：过冲弹性滑动 + **放大脉冲**。
     *
     * 滴像一颗放大镜：滑动全程横纵等比缩放（无拉伸变形），峰值约 1.45 倍
     * 后收回落位。
     *
     * 脉冲由挂在 DecorView 上的独立玻璃滴执行：平台视图被包装容器裁剪在
     * 自身边界内，滴放大后超出边界必须画在平台视图之外。decor 滴折射整个
     * 窗口的真实像素，出界不会黑。拿不到 decor 时退回栏内脉冲，出界部分
     * 靠把折射源临时切到 FlutterView 保证不黑。
     */
    private fun animateDropletTo(index: Int) {
        val tab = tabs.getOrNull(index)?.root ?: return
        if (tab.width <= 0) return
        syncDropletSize(tab.width, tab.height)

        settleAnimator?.cancel()
        val startX = droplet.translationX
        val targetX = (tabsRow.left + tab.left - paddingLeft).toFloat()
        val targetY = (tabsRow.top + tab.top - paddingTop).toFloat()
        val dist = targetX - startX
        if (abs(dist) < 0.5f) {
            syncDroplet()
            return
        }

        // 峰值缩放：横纵等比放大约 1.45 倍（以导航栏垂直中线为放大中心；
        // 峰值过大会让滴大幅顶出栏外、上半压到迷你播放器，观感偏上）
        val peakScale = 1.45f
        val overshoot = OvershootInterpolator(1.1f)

        val overlay = beginOverlayPulse(tab.width, tab.height)
        val useOverlay = overlay != null
        val target: View = overlay ?: droplet
        val baseX = if (useOverlay) 0f else startX
        if (!useOverlay) {
            // 兜底：滴放大后会出界，折射源切到 FlutterView（页面原始内容，出界不黑）
            flutterBackdrop?.let { droplet.backdropSource = it }
        }

        settleAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 520
            addUpdateListener { anim ->
                val t = anim.animatedValue as Float
                // 放大→缩小：前 42% 冲到峰值，之后回落到 1
                val pulse = if (t < 0.42f) {
                    val u = t / 0.42f
                    1f - (1f - u) * (1f - u)
                } else {
                    val u = (t - 0.42f) / 0.58f
                    1f - easeInOut(u)
                }
                // 横纵同比例缩放：滴就是一颗移动的放大镜
                val scale = 1f + (peakScale - 1f) * pulse
                target.scaleX = scale
                target.scaleY = scale
                target.translationX = baseX + dist * overshoot.getInterpolation(t)
                if (!useOverlay) target.translationY = targetY
                // 折射内容取决于滴与页面的相对位置，移动中必须逐帧重採
                target.invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                private var canceled = false
                override fun onAnimationCancel(animation: android.animation.Animator) {
                    canceled = true
                }

                override fun onAnimationEnd(animation: android.animation.Animator) {
                    if (overlay != null) {
                        // 取消（拖拽接管/重定向）时滴保持脉冲当前可视位置，保证连续；
                        // 正常结束直接交给 syncDroplet 落位
                        if (canceled) {
                            droplet.scaleX = overlay.scaleX
                            droplet.scaleY = overlay.scaleY
                            droplet.translationX = startX + overlay.translationX
                            droplet.translationY = targetY
                            droplet.invalidate()
                        }
                        removeOverlayPulse(overlay)
                    } else {
                        // 无论是否被打断，先恢复折射源为默认父容器（bar 自身）
                        droplet.backdropSource = null
                    }
                    // cancel() 也会走到这里：动画中途重定向时不能落位，
                    // 否则滴会瞬移到新目标、新动画因距离为 0 而不播
                    if (!canceled) syncDroplet()
                }
            })
            start()
        }
    }

    /**
     * 在窗口 DecorView 上挂一颗独立玻璃滴执行放大脉冲，返回 null 表示拿不到
     * decor（调用方退回栏内脉冲）。滴与栏内滴中心对齐、样式一致；**垂直方向
     * 以导航栏中线为放大中心**（topMargin 按栏高居中，不随标签行的细微偏移
     * 走），横向随栏内滴；折射源用默认的直接父容器（decor），采样覆盖整个
     * 窗口，出界区域折射真实内容不黑。
     */
    private fun beginOverlayPulse(targetW: Int, targetH: Int): LiquidGlassView? {
        pulseOverlay?.let { removeOverlayPulse(it) }
        if (droplet.width <= 0 || droplet.height <= 0) return null
        val decor = resolveDecorView() ?: return null
        val loc = IntArray(2)
        droplet.getLocationOnScreen(loc)
        val barLoc = IntArray(2)
        getLocationOnScreen(barLoc)
        val overlay = LiquidGlassView(context).apply {
            enablePressEffect = false
            // 只折射不模糊，与栏内滴一致（iOS 的滴是清透的放大镜）
            enableBackdropBlur = false
            cornerRadius = 999f
            bevelWidth = dpF(8)
            refractionHeight = dpF(4)
            dispersionStrength = 0.04f
            overLight = droplet.overLight
            // 纯视觉元素：不吃触摸、不进无障碍
            isClickable = false
            isFocusable = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val lp = FrameLayout.LayoutParams(targetW, targetH)
        // 横向：与栏内滴左缘对齐（动画再用 translationX 驱动）
        lp.leftMargin = loc[0] + (droplet.width - targetW) / 2
        // 纵向：按导航栏中线居中——放大中心恒在栏的垂直中点
        lp.topMargin = barLoc[1] + (height - targetH) / 2
        return try {
            droplet.visibility = GONE
            decor.addView(overlay, lp)
            pulseOverlay = overlay
            overlay
        } catch (e: Exception) {
            Log.e(TAG, "attach pulse overlay failed", e)
            droplet.visibility = VISIBLE
            null
        }
    }

    private fun removeOverlayPulse(overlay: LiquidGlassView) {
        if (pulseOverlay === overlay) pulseOverlay = null
        (overlay.parent as? ViewGroup)?.removeView(overlay)
        droplet.visibility = VISIBLE
    }

    private fun resolveDecorView(): ViewGroup? {
        var c: Context? = context
        while (c is ContextWrapper) {
            if (c is Activity) return c.window?.decorView as? ViewGroup
            c = c.baseContext
        }
        return null
    }

    /** 平滑的缓入缓出（脉冲收尾用，比线性更「液体」） */
    private fun easeInOut(t: Float): Float = t * t * (3f - 2f * t)

    /**
     * 按当前横向拉伸量钳制平移：拖拽时用（拖拽不切折射源，出界会黑），
     * 保证滴的可视边缘（含缩放外扩）始终留在标签行内
     */
    private fun clampDropletX(x: Float, scaleX: Float): Float {
        val rowW = tabsRow.width.toFloat()
        val w = droplet.width.toFloat()
        if (rowW <= 0f || w <= 0f) return x
        val bulge = (scaleX - 1f) * w / 2f
        val minX = bulge
        val maxX = rowW - w - bulge
        return if (minX <= maxX) x.coerceIn(minX, maxX) else (rowW - w) / 2f
    }

    // ==================== 触摸：点击选择 + 拖拽玻璃滴 ====================

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean = true

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                dragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (!dragging && abs(event.x - downX) > touchSlop) {
                    dragging = true
                    settleAnimator?.cancel()
                    // 拖拽可能打断放大脉冲：恢复折射源为默认父容器
                    droplet.backdropSource = null
                    // 按住拖拽时玻璃滴微微鼓起（iOS 手感）
                    droplet.scaleX = 1.06f
                    droplet.scaleY = 1.06f
                }
                if (dragging) dragDropletTo(event.x)
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (dragging) {
                    dragging = false
                    selectTab(nearestTabIndex(), animate = true)
                } else {
                    selectTab(tabIndexAt(event.x), animate = true)
                }
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                dragging = false
                animateDropletTo(selected)
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    /** 玻璃滴跟手：中心对齐手指，按当前鼓起量钳制在标签行范围内 */
    private fun dragDropletTo(x: Float) {
        if (tabsRow.width <= 0 || droplet.width <= 0) return
        val local = x - paddingLeft - droplet.width / 2f
        droplet.translationX = clampDropletX(local, droplet.scaleX)
        droplet.invalidate()
    }

    /** 拖拽松手：按玻璃滴中心找最近的标签 */
    private fun nearestTabIndex(): Int {
        val centerX = droplet.translationX + droplet.width / 2f
        var best = selected
        var bestDist = Float.MAX_VALUE
        tabs.forEachIndexed { index, tab ->
            val tabCenter = tab.root.left + tab.root.width / 2f
            val d = abs(tabCenter - centerX)
            if (d < bestDist) {
                bestDist = d
                best = index
            }
        }
        return best
    }

    /** 点击位置对应的标签（相对 bar 的 x 坐标） */
    private fun tabIndexAt(x: Float): Int {
        val local = x - tabsRow.left
        tabs.forEachIndexed { index, tab ->
            if (local < tab.root.right) return index
        }
        return (tabs.size - 1).coerceAtLeast(0)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
    private fun dpF(v: Int): Float = v * resources.displayMetrics.density
}
