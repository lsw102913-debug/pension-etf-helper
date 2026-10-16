package com.antigravity.pension.pension_etf_helper

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.antigravity.pension/mstock"
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var orderItems: List<Map<String, Any>> = emptyList()
    private var currentIndex: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                "launchMStock" -> {
                    val launched = launchMiraeAssetApp()
                    result.success(launched)
                }
                "startFloatingRemote" -> {
                    @Suppress("UNCHECKED_CAST")
                    val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                    val startIndex = call.argument<Int>("startIndex") ?: 0
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        result.success(false)
                    } else {
                        orderItems = items
                        currentIndex = startIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0))
                        showFloatingOverlay()
                        result.success(true)
                    }
                }
                "stopFloatingRemote" -> {
                    removeFloatingOverlay()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun launchMiraeAssetApp(): Boolean {
        val packages = listOf(
            "com.miraeasset.trade",
            "com.miraeasset.mstock",
            "com.miraeasset.account"
        )
        for (pkg in packages) {
            val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
                return true
            }
        }
        try {
            val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.miraeasset.trade"))
            marketIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(marketIntent)
        } catch (e: Exception) {
            Toast.makeText(this, "미래에셋 M-STOCK 앱이 설치되어 있지 않습니다.", Toast.LENGTH_SHORT).show()
        }
        return false
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    private fun copyToClipboard(label: String, text: String, toastMsg: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
        Toast.makeText(this, toastMsg, Toast.LENGTH_SHORT).show()
    }

    private fun showFloatingOverlay() {
        removeFloatingOverlay()
        if (orderItems.isEmpty()) return

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#EE1A233A"))
                cornerRadius = dp(16).toFloat()
                setStroke(dp(2), Color.parseColor("#FF6D00"))
            }
        }

        // Header row: badge + title + close button
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val titleText = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTypeface(typeface, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        val closeBtn = TextView(this).apply {
            text = "✕ 닫기"
            setTextColor(Color.parseColor("#FFAB91"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dp(8), dp(4), dp(4), dp(4))
            setOnClickListener { removeFloatingOverlay() }
        }

        headerRow.addView(titleText)
        headerRow.addView(closeBtn)

        // Sub row: quantity & price highlight
        val detailText = TextView(this).apply {
            setTextColor(Color.parseColor("#FFD54F"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(4), 0, dp(8))
        }

        // Action buttons row
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        fun makeBtn(label: String, bgColor: String, textColor: String = "#FFFFFF"): Button {
            return Button(this).apply {
                text = label
                setTextColor(Color.parseColor(textColor))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                isAllCaps = false
                minHeight = dp(34)
                minimumHeight = dp(34)
                setPadding(dp(8), dp(4), dp(8), dp(4))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor(bgColor))
                    cornerRadius = dp(8).toFloat()
                }
                layoutParams = LinearLayout.LayoutParams(0, dp(36), 1f).apply {
                    marginEnd = dp(4)
                }
            }
        }

        val prevBtn = makeBtn("◀ 이전", "#37474F")
        val copyCodeBtn = makeBtn("종목복사", "#0277BD")
        val copyQtyBtn = makeBtn("수량복사", "#2E7D32")
        val nextBtn = makeBtn("다음 ▶", "#EF6C00").apply {
            (layoutParams as LinearLayout.LayoutParams).marginEnd = 0
        }

        fun updateUI(autoCopyQty: Boolean) {
            val item = orderItems[currentIndex]
            val name = item["name"]?.toString() ?: ""
            val code = item["code"]?.toString() ?: ""
            val qty = item["qty"]?.toString() ?: "0"
            val price = item["priceFormatted"]?.toString() ?: ""
            val budget = item["budgetFormatted"]?.toString() ?: ""

            titleText.text = "[${currentIndex + 1}/${orderItems.size}] $name ($code)"
            detailText.text = "👉 매수: ${qty}주  |  현재가 ${price}원 (예산 ${budget})"
            copyQtyBtn.text = "수량(${qty})복사"

            prevBtn.alpha = if (currentIndex > 0) 1.0f else 0.4f
            nextBtn.text = if (currentIndex < orderItems.size - 1) "다음 ▶" else "완료 ✓"

            if (autoCopyQty) {
                copyToClipboard("order_qty", qty, "[${currentIndex + 1}/${orderItems.size}] $name: ${qty}주 자동 복사됨!")
            }
        }

        prevBtn.setOnClickListener {
            if (currentIndex > 0) {
                currentIndex--
                updateUI(true)
            }
        }

        copyCodeBtn.setOnClickListener {
            val item = orderItems[currentIndex]
            val name = item["name"]?.toString() ?: ""
            val code = item["code"]?.toString() ?: ""
            copyToClipboard("order_code", code, "$name 종목코드($code) 복사됨!")
        }

        copyQtyBtn.setOnClickListener {
            val item = orderItems[currentIndex]
            val name = item["name"]?.toString() ?: ""
            val qty = item["qty"]?.toString() ?: "0"
            copyToClipboard("order_qty", qty, "$name 매수 수량(${qty}주) 복사됨!")
        }

        nextBtn.setOnClickListener {
            if (currentIndex < orderItems.size - 1) {
                currentIndex++
                updateUI(true)
            } else {
                Toast.makeText(this, "6개 종목 주문 가이드 완료! 리모컨을 닫습니다.", Toast.LENGTH_SHORT).show()
                removeFloatingOverlay()
            }
        }

        btnRow.addView(prevBtn)
        btnRow.addView(copyCodeBtn)
        btnRow.addView(copyQtyBtn)
        btnRow.addView(nextBtn)

        root.addView(headerRow)
        root.addView(detailText)
        root.addView(btnRow)

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.94).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(48)
        }

        // Allow dragging vertically
        var initialY = 0
        var initialTouchY = 0f
        headerRow.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = params.y
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(root, params)
                    true
                }
                else -> false
            }
        }

        floatingView = root
        windowManager?.addView(root, params)
        updateUI(true)
    }

    private fun removeFloatingOverlay() {
        floatingView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {}
        }
        floatingView = null
    }

    override fun onDestroy() {
        removeFloatingOverlay()
        super.onDestroy()
    }
}
