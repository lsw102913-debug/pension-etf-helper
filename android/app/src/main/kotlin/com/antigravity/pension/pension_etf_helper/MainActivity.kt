package com.antigravity.pension.pension_etf_helper

import android.app.AlarmManager
import android.app.PendingIntent
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
import android.os.Bundle
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.antigravity.pension/mstock"
    private var methodChannel: MethodChannel? = null
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var calibrationView: View? = null
    private var orderItems: List<Map<String, Any>> = emptyList()
    private var currentIndex: Int = 0
    private var pendingAutoTrigger: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra("auto_trigger", false) == true) {
            pendingAutoTrigger = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("auto_trigger", false)) {
            pendingAutoTrigger = true
            methodChannel?.invokeMethod("onAlarmTriggered", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = ch

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeAutoTrigger" -> {
                    val triggered = pendingAutoTrigger
                    pendingAutoTrigger = false
                    result.success(triggered)
                }
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
                    }
                    result.success(true)
                }
                "isAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibilityPermission" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    Toast.makeText(
                        this,
                        "[설치된 앱] → [연금모으기 6종목 풀오토 자동주문]을 켜주세요!",
                        Toast.LENGTH_LONG
                    ).show()
                    result.success(true)
                }
                "launchMStock" -> {
                    result.success(launchMiraeAssetApp())
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
                    MStockAutoOrderService.instance?.stopSequence()
                    removeCalibrationOverlay()
                    removeFloatingOverlay()
                    result.success(true)
                }
                "scheduleWeeklyAlarm" -> {
                    val weekday = call.argument<Int>("weekday") ?: 1 // 1=Mon .. 5=Fri
                    val hour = call.argument<Int>("hour") ?: 15
                    val minute = call.argument<Int>("minute") ?: 10
                    val msg = scheduleWeeklyExactAlarm(weekday, hour, minute)
                    result.success(msg)
                }
                "cancelWeeklyAlarm" -> {
                    cancelWeeklyExactAlarm()
                    result.success(true)
                }
                "triggerTestAlarmIn5Seconds" -> {
                    scheduleTestAlarm5Sec()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        if (MStockAutoOrderService.instance != null) return true
        val expectedComponentName = "$packageName/${MStockAutoOrderService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains(expectedComponentName) ||
                enabledServices.contains(MStockAutoOrderService::class.java.simpleName)
    }

    private fun scheduleWeeklyExactAlarm(isoWeekday: Int, hour: Int, minute: Int): String {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (_: Exception) {}
        }

        // Convert ISO weekday (1=Mon..7=Sun) to Calendar dayOfWeek (Sunday=1, Monday=2..Saturday=7)
        val calDayOfWeek = if (isoWeekday == 7) Calendar.SUNDAY else isoWeekday + 1
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.DAY_OF_WEEK, calDayOfWeek)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) {
                add(Calendar.WEEK_OF_YEAR, 1)
            }
        }

        val intent = Intent(this, AlarmReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getBroadcast(this, 1001, intent, flags)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.timeInMillis, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, target.timeInMillis, pi)
            }
        } catch (_: SecurityException) {
            am.set(AlarmManager.RTC_WAKEUP, target.timeInMillis, pi)
        }

        val month = target.get(Calendar.MONTH) + 1
        val day = target.get(Calendar.DAY_OF_MONTH)
        val hh = target.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
        val mm = target.get(Calendar.MINUTE).toString().padStart(2, '0')
        return "${month}월 ${day}일 $hh:$mm 자동 실행 예약됨"
    }

    private fun cancelWeeklyExactAlarm() {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getBroadcast(this, 1001, intent, flags)
        am.cancel(pi)
    }

    private fun scheduleTestAlarm5Sec() {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getBroadcast(this, 1002, intent, flags)
        val triggerAt = System.currentTimeMillis() + 5000L
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
        } catch (_: SecurityException) {
            am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi)
        }
        Toast.makeText(this, "5초 뒤 예약 자동 실행이 작동합니다!", Toast.LENGTH_SHORT).show()
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
        } catch (_: Exception) {
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
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#F2141E30"))
                cornerRadius = dp(16).toFloat()
                setStroke(dp(2), Color.parseColor("#FF6D00"))
            }
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val titleText = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(typeface, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        val calibrateBtn = TextView(this).apply {
            text = "🎯 위치맞춤"
            setTextColor(Color.parseColor("#80D8FF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setPadding(dp(6), dp(4), dp(6), dp(4))
            setOnClickListener { showCalibrationOverlay() }
        }

        val closeBtn = TextView(this).apply {
            text = "✕ 닫기"
            setTextColor(Color.parseColor("#FFAB91"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setPadding(dp(6), dp(4), dp(4), dp(4))
            setOnClickListener {
                MStockAutoOrderService.instance?.stopSequence()
                removeCalibrationOverlay()
                removeFloatingOverlay()
            }
        }

        headerRow.addView(titleText)
        headerRow.addView(calibrateBtn)
        headerRow.addView(closeBtn)

        val detailText = TextView(this).apply {
            setTextColor(Color.parseColor("#FFD54F"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(4), 0, dp(6))
        }

        // Full-Auto Control Row (Login -> 1-Tap 6-Item Full Auto)
        val autoRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(6))
        }

        val fullAutoBtn = Button(this).apply {
            text = "🚀 로그인 완료! 6종목 풀오토 자동매수 시작"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            setTypeface(typeface, Typeface.BOLD)
            isAllCaps = false
            minHeight = dp(38)
            minimumHeight = dp(38)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#D84315"))
                cornerRadius = dp(10).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(0, dp(38), 1f)
        }

        autoRow.addView(fullAutoBtn)

        // Manual / Step-by-step Row
        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        fun makeBtn(label: String, bgColor: String): Button {
            return Button(this).apply {
                text = label
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                isAllCaps = false
                minHeight = dp(32)
                minimumHeight = dp(32)
                setPadding(dp(4), dp(2), dp(4), dp(2))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor(bgColor))
                    cornerRadius = dp(8).toFloat()
                }
                layoutParams = LinearLayout.LayoutParams(0, dp(34), 1f).apply {
                    marginEnd = dp(4)
                }
            }
        }

        val prevBtn = makeBtn("◀ 이전", "#37474F")
        val copyCodeBtn = makeBtn("코드복사", "#0277BD")
        val copyAsk1Btn = makeBtn("위칸가격", "#6A1B9A")
        val copyQtyBtn = makeBtn("수량복사", "#2E7D32")
        val nextBtn = makeBtn("다음 ▶", "#EF6C00").apply {
            (layoutParams as LinearLayout.LayoutParams).marginEnd = 0
        }

        fun updateUI(autoCopyQty: Boolean) {
            val item = orderItems[currentIndex]
            val name = item["name"]?.toString() ?: ""
            val code = item["code"]?.toString() ?: ""
            val qty = item["qty"]?.toString() ?: "0"
            val ask1 = item["ask1Formatted"]?.toString() ?: ""
            val ask1Raw = item["ask1Raw"]?.toString() ?: ""

            titleText.text = "[${currentIndex + 1}/${orderItems.size}] $name ($code)"
            detailText.text = "⚡위칸(+5원): ${ask1}원 | 매수: ${qty}주"
            copyQtyBtn.text = "수량(${qty})"
            copyAsk1Btn.text = "위칸(${ask1Raw})"

            prevBtn.alpha = if (currentIndex > 0) 1.0f else 0.4f
            nextBtn.text = if (currentIndex < orderItems.size - 1) "다음 ▶" else "완료 ✓"

            if (autoCopyQty) {
                copyToClipboard("order_qty", qty, "[${currentIndex + 1}/${orderItems.size}] $name: ${qty}주 복사됨 (위칸 ${ask1}원)")
            }
        }

        fullAutoBtn.setOnClickListener {
            val svc = MStockAutoOrderService.instance
            if (svc == null) {
                Toast.makeText(
                    this,
                    "풀오토 자동터치를 위해 [연금모으기 6종목 풀오토 자동주문] 접근성 권한을 먼저 켜주세요!",
                    Toast.LENGTH_LONG
                ).show()
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return@setOnClickListener
            }

            if (MStockAutoOrderService.isRunningAuto) {
                svc.stopSequence()
                fullAutoBtn.text = "🚀 로그인 완료! 6종목 풀오토 자동매수 시작"
                fullAutoBtn.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#D84315"))
                    cornerRadius = dp(10).toFloat()
                }
                updateUI(false)
            } else {
                fullAutoBtn.text = "⏹ 풀오토 자동주문 진행 중 (터치 시 즉시 정지)"
                fullAutoBtn.background = GradientDrawable().apply {
                    setColor(Color.parseColor("#B71C1C"))
                    cornerRadius = dp(10).toFloat()
                }
                val dm = resources.displayMetrics
                svc.runFullAutoOrderSequence(
                    orderItems,
                    currentIndex,
                    dm.widthPixels,
                    dm.heightPixels
                ) { idx, statusText, finished ->
                    runOnUiThread {
                        currentIndex = idx
                        detailText.text = statusText
                        if (finished) {
                            fullAutoBtn.text = "✅ 6종목 풀오토 완료! (다시 시작하려면 터치)"
                            fullAutoBtn.background = GradientDrawable().apply {
                                setColor(Color.parseColor("#2E7D32"))
                                cornerRadius = dp(10).toFloat()
                            }
                        }
                    }
                }
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
            copyToClipboard("code", item["code"]?.toString() ?: "", "종목코드 복사됨!")
        }

        copyAsk1Btn.setOnClickListener {
            val item = orderItems[currentIndex]
            val raw = item["ask1Raw"]?.toString() ?: ""
            copyToClipboard("ask1", raw, "현재가 바로 위 칸(${raw}원) 복사됨!")
        }

        copyQtyBtn.setOnClickListener {
            val item = orderItems[currentIndex]
            val qty = item["qty"]?.toString() ?: "0"
            copyToClipboard("qty", qty, "매수 수량(${qty}주) 복사됨!")
        }

        nextBtn.setOnClickListener {
            if (currentIndex < orderItems.size - 1) {
                currentIndex++
                updateUI(true)
            } else {
                Toast.makeText(this, "6개 종목 주문 완료! 리모컨을 닫습니다.", Toast.LENGTH_SHORT).show()
                removeFloatingOverlay()
            }
        }

        btnRow.addView(prevBtn)
        btnRow.addView(copyCodeBtn)
        btnRow.addView(copyAsk1Btn)
        btnRow.addView(copyQtyBtn)
        btnRow.addView(nextBtn)

        root.addView(headerRow)
        root.addView(detailText)
        root.addView(autoRow)
        root.addView(btnRow)

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.95).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(42)
        }

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

    /**
     * M-STOCK 화면 위에서 5개 자동터치 버튼 위치를 손가락으로 드래그해 맞추는 영점 조절 오버레이
     */
    private fun showCalibrationOverlay() {
        removeCalibrationOverlay()
        val wm = windowManager ?: (getSystemService(Context.WINDOW_SERVICE) as WindowManager)
        val dm = resources.displayMetrics
        val sw = dm.widthPixels
        val sh = dm.heightPixels

        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#55000000"))
        }

        val guideBanner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#EE1E293B"))
                cornerRadius = dp(12).toFloat()
            }
        }

        val guideText = TextView(this).apply {
            text = "🎯 5개 동그라미를 M-STOCK 매수 화면의 실제 버튼 위치로 드래그한 뒤 [위치 저장]을 눌러주세요!"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
        }

        val saveBtn = Button(this).apply {
            text = "✅ 5개 버튼 위치 저장 완료"
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#2E7D32"))
                cornerRadius = dp(8).toFloat()
            }
        }

        guideBanner.addView(guideText)
        guideBanner.addView(saveBtn)
        container.addView(
            guideBanner,
            FrameLayout.LayoutParams(
                (sw * 0.92).toInt(),
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).apply { bottomMargin = dp(40) }
        )

        val pointsSpec = listOf(
            Triple("pt1", "① 종목검색", MStockAutoOrderService.getPoint(this, "pt1", sw * 0.35f, sh * 0.11f)),
            Triple("pt2", "② 위칸호가(+5원)", MStockAutoOrderService.getPoint(this, "pt2", sw * 0.22f, sh * 0.44f)),
            Triple("pt3", "③ 수량입력칸", MStockAutoOrderService.getPoint(this, "pt3", sw * 0.72f, sh * 0.46f)),
            Triple("pt4", "④ 매수버튼", MStockAutoOrderService.getPoint(this, "pt4", sw * 0.72f, sh * 0.86f)),
            Triple("pt5", "⑤ 주문확인", MStockAutoOrderService.getPoint(this, "pt5", sw * 0.68f, sh * 0.64f))
        )

        val currentCoords = mutableMapOf<String, Pair<Float, Float>>()

        for ((key, label, initPt) in pointsSpec) {
            currentCoords[key] = initPt
            val badge = TextView(this).apply {
                text = label
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                setTypeface(typeface, Typeface.BOLD)
                setPadding(dp(10), dp(8), dp(10), dp(8))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#E6D84315"))
                    cornerRadius = dp(20).toFloat()
                    setStroke(dp(2), Color.YELLOW)
                }
            }

            val lp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                leftMargin = (initPt.first - dp(45)).toInt().coerceIn(0, sw - dp(90))
                topMargin = (initPt.second - dp(20)).toInt().coerceIn(0, sh - dp(60))
            }

            var startX = 0
            var startY = 0
            var touchX = 0f
            var touchY = 0f
            badge.setOnTouchListener { v, ev ->
                when (ev.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = lp.leftMargin
                        startY = lp.topMargin
                        touchX = ev.rawX
                        touchY = ev.rawY
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        lp.leftMargin = (startX + (ev.rawX - touchX).toInt()).coerceIn(0, sw - v.width)
                        lp.topMargin = (startY + (ev.rawY - touchY).toInt()).coerceIn(0, sh - v.height)
                        v.layoutParams = lp
                        currentCoords[key] = Pair(
                            lp.leftMargin + v.width / 2f,
                            lp.topMargin + v.height / 2f
                        )
                        true
                    }
                    else -> false
                }
            }

            container.addView(badge, lp)
        }

        saveBtn.setOnClickListener {
            for ((key, pt) in currentCoords) {
                MStockAutoOrderService.savePoint(this, key, pt.first, pt.second)
            }
            Toast.makeText(this, "내 폰 M-STOCK 5개 터치 위치가 저장되었습니다!", Toast.LENGTH_SHORT).show()
            removeCalibrationOverlay()
        }

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )

        calibrationView = container
        wm.addView(container, params)
    }

    private fun removeCalibrationOverlay() {
        calibrationView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {}
        }
        calibrationView = null
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
        MStockAutoOrderService.instance?.stopSequence()
        removeCalibrationOverlay()
        removeFloatingOverlay()
        super.onDestroy()
    }
}
