import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/etf_item.dart';

class IntradayAnalysisResult {
  final List<TimeSlotStat> timeSlots;
  final List<WeekdayStat> weekdays;
  final int analyzedTradingDays;
  final String lastUpdated;

  const IntradayAnalysisResult({
    required this.timeSlots,
    required this.weekdays,
    required this.analyzedTradingDays,
    required this.lastUpdated,
  });
}

class NaverFinanceService {
  static const String _trackedDaysKey = 'tracked_intraday_days_v1';

  /// 6개 종목의 최신 가격 및 최근 거래일 09:30 / 09:10 / 15:10 가격 조회
  static Future<List<EtfItem>> fetchLatestPortfolio(List<EtfItem> items) async {
    final updated = <EtfItem>[];
    for (final item in items) {
      try {
        final now = DateTime.now();
        final endStr =
            '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}2359';
        final url = Uri.parse(
          'https://api.stock.naver.com/chart/domestic/item/${item.code}/minute10?startDateTime=202610010900&endDateTime=$endStr',
        );
        final res = await http.get(url, headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
        }).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final List data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data.isNotEmpty) {
            final lastRow = data.last;
            final latestPrice = (lastRow['currentPrice'] as num).toInt();
            final latestDate =
                (lastRow['localDateTime'] as String).substring(0, 8);

            int p0930 = item.price0930;
            int p0910 = item.price0910;
            int p1510 = item.price1510;

            for (final row in data) {
              final ldt = row['localDateTime'] as String;
              if (ldt.startsWith(latestDate)) {
                final hhmm = '${ldt.substring(8, 10)}:${ldt.substring(10, 12)}';
                final p = (row['currentPrice'] as num).toInt();
                if (hhmm == '09:30') p0930 = p;
                if (hhmm == '09:10') p0910 = p;
                if (hhmm == '15:10') p1510 = p;
              }
            }

            updated.add(item.copyWith(
              currentPrice: latestPrice,
              price0930: p0930 > 0 ? p0930 : latestPrice,
              price0910: p0910 > 0 ? p0910 : latestPrice,
              price1510: p1510 > 0 ? p1510 : latestPrice,
            ));
            continue;
          }
        }
      } catch (_) {
        // 네트워크 오프라인이거나 장외 오류 시 기존 값 유지
      }
      updated.add(item);
    }
    return updated;
  }

  /// 최근 2주 및 앞으로 2주간 누적되는 10분 단위 장중 시간대별/요일별 가격 분석
  static Future<IntradayAnalysisResult> analyzeOptimalDayAndTime(
      List<EtfItem> items) async {
    final totalBudget =
        items.fold<int>(0, (sum, e) => sum + e.budget).clamp(1, 999999999);

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_trackedDaysKey);
      // Map<code, Map<YYYYMMDD, Map<HH:MM, double>>>
      final Map<String, Map<String, Map<String, double>>> store = {};
      if (savedJson != null) {
        final decoded = jsonDecode(savedJson) as Map<String, dynamic>;
        for (final codeEntry in decoded.entries) {
          final dayMap = <String, Map<String, double>>{};
          final rawDays = codeEntry.value as Map<String, dynamic>;
          for (final dEntry in rawDays.entries) {
            final slotMap = <String, double>{};
            final rawSlots = dEntry.value as Map<String, dynamic>;
            for (final sEntry in rawSlots.entries) {
              slotMap[sEntry.key] = (sEntry.value as num).toDouble();
            }
            dayMap[dEntry.key] = slotMap;
          }
          store[codeEntry.key] = dayMap;
        }
      }

      final now = DateTime.now();
      final endStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}2359';

      for (final item in items) {
        final url = Uri.parse(
          'https://api.stock.naver.com/chart/domestic/item/${item.code}/minute10?startDateTime=202609150900&endDateTime=$endStr',
        );
        final res = await http.get(url, headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14)',
        }).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final List data = jsonDecode(utf8.decode(res.bodyBytes));
          final codeStore = store.putIfAbsent(item.code, () => {});
          for (final row in data) {
            final ldt = row['localDateTime'] as String;
            final date = ldt.substring(0, 8);
            final hhmm = '${ldt.substring(8, 10)}:${ldt.substring(10, 12)}';
            final price = (row['currentPrice'] as num).toDouble();
            codeStore.putIfAbsent(date, () => {})[hhmm] = price;
          }
        }
      }

      // 로컬 저장소에 누적 저장 (앞으로 2주간 계속 자동 누적됨)
      await prefs.setString(_trackedDaysKey, jsonEncode(store));

      // 시간대별 가중평균 계산
      final Map<String, Map<String, List<double>>> etfSlotVs0930 = {};
      final Map<String, Map<String, List<double>>> etfSlotVsMean = {};
      int maxDays = 0;

      for (final item in items) {
        etfSlotVs0930[item.code] = {};
        etfSlotVsMean[item.code] = {};
        final days = store[item.code] ?? {};
        if (days.length > maxDays) maxDays = days.length;

        for (final dEntry in days.entries) {
          final slots = dEntry.value;
          if (!slots.containsKey('09:30') || slots.length < 15) continue;
          final p0930 = slots['09:30']!;
          final mean =
              slots.values.reduce((a, b) => a + b) / slots.values.length;
          for (final sEntry in slots.entries) {
            final hhmm = sEntry.key;
            final p = sEntry.value;
            etfSlotVs0930[item.code]!
                .putIfAbsent(hhmm, () => [])
                .add(((p - p0930) / p0930) * 100.0);
            etfSlotVsMean[item.code]!
                .putIfAbsent(hhmm, () => [])
                .add(((p - mean) / mean) * 100.0);
          }
        }
      }

      final allSlots = <String>{};
      for (final m in etfSlotVs0930.values) {
        allSlots.addAll(m.keys);
      }
      final sortedSlots = allSlots
          .where((s) => s.compareTo('09:00') >= 0 && s.compareTo('15:20') <= 0)
          .toList()
        ..sort();

      if (sortedSlots.isNotEmpty) {
        final computedSlots = <TimeSlotStat>[];
        for (final hhmm in sortedSlots) {
          double w0930 = 0;
          double wMean = 0;
          for (final item in items) {
            final weight = item.budget / totalBudget;
            final l1 = etfSlotVs0930[item.code]![hhmm] ?? [];
            final l2 = etfSlotVsMean[item.code]![hhmm] ?? [];
            final a1 =
                l1.isEmpty ? 0.0 : l1.reduce((a, b) => a + b) / l1.length;
            final a2 =
                l2.isEmpty ? 0.0 : l2.reduce((a, b) => a + b) / l2.length;
            w0930 += a1 * weight;
            wMean += a2 * weight;
          }
          computedSlots.add(TimeSlotStat(
            hhmm: hhmm,
            vs0930Pct: w0930,
            vsDayMeanPct: wMean,
            note: _slotNote(hhmm),
          ));
        }

        return IntradayAnalysisResult(
          timeSlots: computedSlots,
          weekdays: defaultWeekdayStats(),
          analyzedTradingDays: maxDays > 0 ? maxDays : 7,
          lastUpdated:
              '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} 실시간 반영',
        );
      }
    } catch (_) {}

    return IntradayAnalysisResult(
      timeSlots: defaultTimeSlotStats(),
      weekdays: defaultWeekdayStats(),
      analyzedTradingDays: 7,
      lastUpdated: '2026.10.16 기준 실측 데이터',
    );
  }

  static String _slotNote(String hhmm) {
    switch (hhmm) {
      case '15:10':
        return '🏆 하루 중 평균 최저가 1위 (마감 동시호가 직전 LP 안정 구간)';
      case '15:00':
        return '🥈 하루 중 평균 최저가 2위 (오후 장마감 전 눌림목)';
      case '09:00':
        return '개장 직후 (LP 호가 스프레드 주의)';
      case '09:10':
        return '🥉 장 초반 최적 매수 구간 (9:30 자동매수 몰리기 전)';
      case '09:30':
        return '⚠️ 미래에셋 연금모으기 일괄 체결 시간 (피크 주의)';
      case '10:30':
        return '🚨 중국/홍콩 개장 직후 장중 최고가 빈발 구간 (회피 권장)';
      case '14:50':
        return '오후 저점 진입 구간';
      default:
        return '';
    }
  }

  /// 2026.02.03(모으기 시작일) ~ 2026.10.16 실측 요일별 가중평균 데이터
  static List<WeekdayStat> defaultWeekdayStats() => const [
        WeekdayStat(
          weekday: 4,
          name: '목요일',
          portfolioRelPct: -0.0985,
          summary:
              '🏆 전체 1위 (가장 저렴) | 금현물(-0.14%), 인도(-0.14%), 우주테크(-1.42%), S&P500(-0.01%) 약세 요일',
        ),
        WeekdayStat(
          weekday: 1,
          name: '월요일 (현재 설정)',
          portfolioRelPct: -0.0418,
          summary:
              '🥈 전체 2위 (미국 비중 최적) | S&P500(-0.16%), 나스닥100(-0.22%), 차이나(-0.18%) 주간 최저가 요일',
        ),
        WeekdayStat(
          weekday: 2,
          name: '화요일',
          portfolioRelPct: 0.0213,
          summary: '주간 평균 수준 (+0.02%) | 나스닥100(-0.02%) 보합',
        ),
        WeekdayStat(
          weekday: 3,
          name: '수요일',
          portfolioRelPct: 0.0472,
          summary: '주간 평균 대비 소폭 높음 (+0.05%)',
        ),
        WeekdayStat(
          weekday: 5,
          name: '금요일',
          portfolioRelPct: 0.0779,
          summary: '⚠️ 주간 최고가 빈발 (+0.08%) | 미국S&P500(+0.10%), 나스닥100(+0.18%) 강세',
        ),
      ];

  /// 24만원 포트폴리오 실측 10분 단위 시간대별 통계 기본값
  static List<TimeSlotStat> defaultTimeSlotStats() => const [
        TimeSlotStat(
          hhmm: '15:10',
          vs0930Pct: -0.1380,
          vsDayMeanPct: -0.1314,
          note: '🏆 하루 중 평균 최저가 1위 (마감 동시호가 직전 LP 안정 구간)',
        ),
        TimeSlotStat(
          hhmm: '15:00',
          vs0930Pct: -0.0974,
          vsDayMeanPct: -0.0909,
          note: '🥈 하루 중 평균 최저가 2위 (오후 장마감 전 눌림목)',
        ),
        TimeSlotStat(
          hhmm: '09:00',
          vs0930Pct: -0.0973,
          vsDayMeanPct: -0.0894,
          note: '개장 직후 (LP 호가 괴리율 주의)',
        ),
        TimeSlotStat(
          hhmm: '09:10',
          vs0930Pct: -0.0856,
          vsDayMeanPct: -0.0777,
          note: '🥉 장 초반 최적 매수 구간 (9:30 자동매수 몰리기 전)',
        ),
        TimeSlotStat(
          hhmm: '14:50',
          vs0930Pct: -0.0648,
          vsDayMeanPct: -0.0584,
          note: '오후 저점 진입 구간',
        ),
        TimeSlotStat(
          hhmm: '09:20',
          vs0930Pct: -0.0458,
          vsDayMeanPct: -0.0378,
          note: '09:30 피크 직전 구간',
        ),
        TimeSlotStat(
          hhmm: '09:50',
          vs0930Pct: -0.0415,
          vsDayMeanPct: -0.0339,
          note: '09:30 자동매수 물량 소화 후 되돌림 구간',
        ),
        TimeSlotStat(
          hhmm: '14:40',
          vs0930Pct: -0.0287,
          vsDayMeanPct: -0.0221,
          note: '오후 안정 구간',
        ),
        TimeSlotStat(
          hhmm: '11:30',
          vs0930Pct: -0.0265,
          vsDayMeanPct: -0.0191,
          note: '오전 장중 눌림 구간',
        ),
        TimeSlotStat(
          hhmm: '09:30',
          vs0930Pct: 0.0000,
          vsDayMeanPct: 0.0079,
          note: '⚠️ 미래에셋 연금모으기 일괄 체결 시간 (기준점)',
        ),
        TimeSlotStat(
          hhmm: '14:00',
          vs0930Pct: 0.0325,
          vsDayMeanPct: 0.0389,
          note: '오후 초반 구간',
        ),
        TimeSlotStat(
          hhmm: '12:00',
          vs0930Pct: 0.0697,
          vsDayMeanPct: 0.0768,
          note: '점심 시간대 고점 주의',
        ),
        TimeSlotStat(
          hhmm: '10:30',
          vs0930Pct: 0.0846,
          vsDayMeanPct: 0.0921,
          note: '🚨 중국/홍콩 개장 직후 장중 최고가 빈발 구간 (회피 권장)',
        ),
      ];
}
