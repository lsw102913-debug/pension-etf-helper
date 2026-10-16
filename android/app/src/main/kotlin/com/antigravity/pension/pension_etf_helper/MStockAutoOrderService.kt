package com.antigravity.pension.pension_etf_helper

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class MStockAutoOrderService : AccessibilityService() {

    companion object {
        var instance: MStockAutoOrderService? = null
        var isRunningAuto: Boolean = false
        private const val PREFS_NAME = "mstock_auto_coords"

        fun savePoint(context: Context, key: String, x: Float, y: Float) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putFloat("${key}_x", x)
                .putFloat("${key}_y", y)
                .apply()
        }

        fun getPoint(context: Context, key: String, defaultX: Float, defaultY: Float): Pair<Float, Float> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val x = prefs.getFloat("${key}_x", defaultX)
            val y = prefs.getFloat("${key}_y", defaultY)
            return Pair(x, y)
        }
    }

    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Events handled on-demand during sequence execution
    }

    override fun onInterrupt() {
        stopSequence()
    }

    override fun onDestroy() {
        stopSequence()
        if (instance == this) instance = null
        super.onDestroy()
    }

    fun stopSequence() {
        isRunningAuto = false
        handler.removeCallbacksAndMessages(null)
    }

    private fun tapScreen(x: Float, y: Float, onDone: (() -> Unit)? = null) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            onDone?.invoke()
            return
        }
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 80)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                onDone?.invoke()
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                onDone?.invoke()
            }
        }, null)
    }

    private fun copyText(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("auto_input", text))
    }

    private fun setFocusedOrMatchingNodeText(text: String, hintKeyword: String? = null): Boolean {
        val root = rootInActiveWindow ?: return false
        // 1. Check currently focused input node
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (focused != null && focused.isEditable) {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            if (focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
                return true
            }
            copyText(text)
            if (focused.performAction(AccessibilityNodeInfo.ACTION_PASTE)) {
                return true
            }
        }
        // 2. Search editable nodes in window
        val editables = mutableListOf<AccessibilityNodeInfo>()
        collectEditableNodes(root, editables)
        for (node in editables) {
            val nodeText = (node.text?.toString() ?: "") + " " + (node.contentDescription?.toString() ?: "")
            if (hintKeyword == null || nodeText.contains(hintKeyword)) {
                val args = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
                }
                if (node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) {
                    return true
                }
            }
        }
        return false
    }

    private fun collectEditableNodes(node: AccessibilityNodeInfo?, out: MutableList<AccessibilityNodeInfo>) {
        if (node == null) return
        if (node.isEditable || node.className?.toString()?.contains("EditText") == true) {
            out.add(node)
        }
        for (i in 0 until node.childCount) {
            collectEditableNodes(node.getChild(i), out)
        }
    }

    private fun clickNodeByText(keywords: List<String>): Boolean {
        val root = rootInActiveWindow ?: return false
        for (kw in keywords) {
            val list = root.findAccessibilityNodeInfosByText(kw)
            if (!list.isNullOrEmpty()) {
                for (node in list) {
                    var target: AccessibilityNodeInfo? = node
                    while (target != null && !target.isClickable) {
                        target = target.parent
                    }
                    if (target != null && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /**
     * 6개 종목 연속 풀오토 주문 시퀀스 실행
     * ① 종목검색창 터치 & 종목코드 입력
     * ② 현재가 바로 위 칸(+5원, 매도 1호가) 호가창 터치
     * ③ 수량 입력칸 터치 & 계산된 수량 입력
     * ④ [현금매수] 버튼 터치
     * ⑤ [주문 확인] 버튼 터치
     */
    fun runFullAutoOrderSequence(
        items: List<Map<String, Any>>,
        startIndex: Int,
        screenW: Int,
        screenH: Int,
        onStatusUpdate: (index: Int, statusText: String, finished: Boolean) -> Unit
    ) {
        stopSequence()
        if (items.isEmpty()) return
        isRunningAuto = true

        // 기본 M-STOCK 주문 화면 비율 좌표 (사용자가 [위치맞춤]으로 언제든 보정 가능)
        val ptSearch = getPoint(this, "pt1", screenW * 0.35f, screenH * 0.11f)
        val ptAsk1 = getPoint(this, "pt2", screenW * 0.22f, screenH * 0.44f)
        val ptQty = getPoint(this, "pt3", screenW * 0.72f, screenH * 0.46f)
        val ptBuy = getPoint(this, "pt4", screenW * 0.72f, screenH * 0.86f)
        val ptConfirm = getPoint(this, "pt5", screenW * 0.68f, screenH * 0.64f)

        fun executeItem(idx: Int) {
            if (!isRunningAuto || idx >= items.size) {
                isRunningAuto = false
                onStatusUpdate(
                    (items.size - 1).coerceAtLeast(0),
                    "✅ 6개 종목 풀오토 주문 시퀀스 완료!",
                    true
                )
                return
            }

            val item = items[idx]
            val name = item["name"]?.toString() ?: ""
            val code = item["code"]?.toString() ?: ""
            val qty = item["qty"]?.toString() ?: "1"
            val ask1 = item["ask1Formatted"]?.toString() ?: ""

            // Step 1: 종목 검색 및 코드 입력
            onStatusUpdate(idx, "🤖 [${idx + 1}/${items.size}] $name: ① 종목($code) 선택 중...", false)
            copyText(code)
            tapScreen(ptSearch.first, ptSearch.second) {
                handler.postDelayed({
                    if (!isRunningAuto) return@postDelayed
                    setFocusedOrMatchingNodeText(code)

                    // Step 2: 현재가 바로 위 칸 (+5원 매도1호가) 터치
                    handler.postDelayed({
                        if (!isRunningAuto) return@postDelayed
                        onStatusUpdate(idx, "🤖 [${idx + 1}/${items.size}] $name: ② 위칸호가(${ask1}원) 선택 중...", false)
                        tapScreen(ptAsk1.first, ptAsk1.second) {
                            // Step 3: 수량 입력칸 터치 및 주수 자동 입력
                            handler.postDelayed({
                                if (!isRunningAuto) return@postDelayed
                                onStatusUpdate(idx, "🤖 [${idx + 1}/${items.size}] $name: ③ 수량(${qty}주) 입력 중...", false)
                                copyText(qty)
                                tapScreen(ptQty.first, ptQty.second) {
                                    handler.postDelayed({
                                        if (!isRunningAuto) return@postDelayed
                                        setFocusedOrMatchingNodeText(qty, "수량")

                                        // Step 4: [현금매수] 버튼 클릭
                                        handler.postDelayed({
                                            if (!isRunningAuto) return@postDelayed
                                            onStatusUpdate(idx, "🤖 [${idx + 1}/${items.size}] $name: ④ 매수 버튼 클릭...", false)
                                            val clickedByText = clickNodeByText(listOf("현금매수", "매수주문"))
                                            if (!clickedByText) {
                                                tapScreen(ptBuy.first, ptBuy.second)
                                            }

                                            // Step 5: [주문확인] 팝업 클릭
                                            handler.postDelayed({
                                                if (!isRunningAuto) return@postDelayed
                                                onStatusUpdate(idx, "🤖 [${idx + 1}/${items.size}] $name: ⑤ 주문 확인 클릭...", false)
                                                val confirmedByText = clickNodeByText(listOf("매수확인", "주문확인", "확인"))
                                                if (!confirmedByText) {
                                                    tapScreen(ptConfirm.first, ptConfirm.second)
                                                }

                                                // 다음 종목으로 이동
                                                handler.postDelayed({
                                                    if (!isRunningAuto) return@postDelayed
                                                    executeItem(idx + 1)
                                                }, 1100)
                                            }, 850)
                                        }, 750)
                                    }, 500)
                                }
                            }, 650)
                        }
                    }, 900)
                }, 600)
            }
        }

        executeItem(startIndex)
    }
}
