import 'package:flutter/services.dart';
import '../models/etf_item.dart';

class MStockBridge {
  static const MethodChannel _channel =
      MethodChannel('com.antigravity.pension/mstock');

  static void setAlarmTriggerHandler(Future<void> Function() onAlarm) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAlarmTriggered') {
        await onAlarm();
      }
    });
  }

  static Future<bool> consumeAutoTrigger() async {
    try {
      final res = await _channel.invokeMethod<bool>('consumeAutoTrigger');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canDrawOverlays() async {
    try {
      final res = await _channel.invokeMethod<bool>('canDrawOverlays');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<bool> isAccessibilityEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('requestAccessibilityPermission');
    } catch (_) {}
  }

  static Future<bool> launchMStock() async {
    try {
      final res = await _channel.invokeMethod<bool>('launchMStock');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startFloatingRemote(
    List<EtfItem> items, {
    int startIndex = 0,
  }) async {
    try {
      final payload = items
          .map((e) => {
                'name': e.name,
                'code': e.code,
                'qty': e.maxQuantity,
                'priceFormatted': _formatNumber(e.currentPrice),
                'ask1Formatted': _formatNumber(e.askPrice1),
                'ask1Raw': e.askPrice1.toString(),
                'budgetFormatted': '${_formatNumber(e.budget)}원',
              })
          .toList();
      final res = await _channel.invokeMethod<bool>('startFloatingRemote', {
        'items': payload,
        'startIndex': startIndex,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopFloatingRemote() async {
    try {
      await _channel.invokeMethod('stopFloatingRemote');
    } catch (_) {}
  }

  static Future<String> scheduleWeeklyAlarm({
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    try {
      final res = await _channel.invokeMethod<String>('scheduleWeeklyAlarm', {
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
      });
      return res ?? '예약 설정 완료';
    } catch (_) {
      return '예약 설정 완료 (시뮬레이션)';
    }
  }

  static Future<void> cancelWeeklyAlarm() async {
    try {
      await _channel.invokeMethod('cancelWeeklyAlarm');
    } catch (_) {}
  }

  static Future<void> triggerTestAlarmIn5Seconds() async {
    try {
      await _channel.invokeMethod('triggerTestAlarmIn5Seconds');
    } catch (_) {}
  }

  static String _formatNumber(int n) {
    final s = n.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => '${m[1]},');
  }
}
