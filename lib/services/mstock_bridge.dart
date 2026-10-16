import 'package:flutter/services.dart';
import '../models/etf_item.dart';

class MStockBridge {
  static const MethodChannel _channel =
      MethodChannel('com.antigravity.pension/mstock');

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

  static String _formatNumber(int n) {
    final s = n.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => '${m[1]},');
  }
}
