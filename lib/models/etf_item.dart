class EtfItem {
  final String code;
  final String name;
  final int budget;
  final int currentPrice;
  final int price0930;
  final int price0910;
  final int price1510;
  final double changeRate;
  final bool isCompleted;

  const EtfItem({
    required this.code,
    required this.name,
    required this.budget,
    required this.currentPrice,
    required this.price0930,
    this.price0910 = 0,
    this.price1510 = 0,
    this.changeRate = 0.0,
    this.isCompleted = false,
  });

  /// 현재가 바로 위 칸 (매도 1호가 = 즉시 체결가, 국내 상장 ETF 호가 단위 +5원)
  int get askPrice1 => currentPrice > 0 ? currentPrice + 5 : 0;

  /// 현재가 바로 위 칸(+5원)으로 주문해도 예산을 절대 초과하지 않는 최대 매수 주수
  int get maxQuantity => askPrice1 > 0 ? budget ~/ askPrice1 : 0;

  /// 위칸(+5원) 기준 실제 주문 소요 금액
  int get totalCost => maxQuantity * askPrice1;

  /// 종목별 예산에서 남는 잔액
  int get remainingBudget => budget - totalCost;

  /// 09:30 가격 대비 1주당 절약 금액 (+면 위칸 즉시체결가가 09:30보다 저렴)
  int get savedPerShareVs0930 => price0930 > 0 ? (price0930 - askPrice1) : 0;

  /// 09:30 가격 대비 총 절약 금액
  int get totalSavedVs0930 => savedPerShareVs0930 * maxQuantity;

  /// 09:30 대비 등락률 (%) - 음수(-)일수록 09:30보다 저렴함
  double get diffPctVs0930 =>
      price0930 > 0 ? ((askPrice1 - price0930) / price0930) * 100.0 : 0.0;

  EtfItem copyWith({
    String? code,
    String? name,
    int? budget,
    int? currentPrice,
    int? price0930,
    int? price0910,
    int? price1510,
    double? changeRate,
    bool? isCompleted,
  }) {
    return EtfItem(
      code: code ?? this.code,
      name: name ?? this.name,
      budget: budget ?? this.budget,
      currentPrice: currentPrice ?? this.currentPrice,
      price0930: price0930 ?? this.price0930,
      price0910: price0910 ?? this.price0910,
      price1510: price1510 ?? this.price1510,
      changeRate: changeRate ?? this.changeRate,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'budget': budget,
        'currentPrice': currentPrice,
        'price0930': price0930,
        'price0910': price0910,
        'price1510': price1510,
        'changeRate': changeRate,
      };

  factory EtfItem.fromJson(Map<String, dynamic> json) => EtfItem(
        code: json['code'] as String,
        name: json['name'] as String,
        budget: (json['budget'] as num).toInt(),
        currentPrice: (json['currentPrice'] as num?)?.toInt() ?? 0,
        price0930: (json['price0930'] as num?)?.toInt() ?? 0,
        price0910: (json['price0910'] as num?)?.toInt() ?? 0,
        price1510: (json['price1510'] as num?)?.toInt() ?? 0,
        changeRate: (json['changeRate'] as num?)?.toDouble() ?? 0.0,
      );

  /// 사용자의 미래에셋 연금 모으기 기본 6종목 (회차당 총 240,000원)
  static List<EtfItem> defaultPortfolio() => <EtfItem>[
        const EtfItem(
          code: '379800',
          name: 'KODEX 미국S&P500',
          budget: 90000,
          currentPrice: 23320,
          price0930: 23365,
          price0910: 23335,
          price1510: 23320,
        ),
        EtfItem(
          code: '0072R0',
          name: 'TIGER KRX금현물',
          budget: 20000,
          currentPrice: 11970,
          price0930: 11995,
          price0910: 11980,
          price1510: 11970,
        ),
        EtfItem(
          code: '283580',
          name: 'KODEX 차이나CSI300',
          budget: 25000,
          currentPrice: 13390,
          price0930: 13415,
          price0910: 13400,
          price1510: 13390,
        ),
        EtfItem(
          code: '453810',
          name: 'KODEX 인도Nifty50',
          budget: 20000,
          currentPrice: 10860,
          price0930: 10880,
          price0910: 10865,
          price1510: 10860,
        ),
        EtfItem(
          code: '379810',
          name: 'KODEX 미국나스닥100',
          budget: 70000,
          currentPrice: 26410,
          price0930: 26460,
          price0910: 26425,
          price1510: 26410,
        ),
        EtfItem(
          code: '0183J0',
          name: 'TIGER 미국우주테크',
          budget: 15000,
          currentPrice: 6435,
          price0930: 6450,
          price0910: 6440,
          price1510: 6435,
        ),
      ];
}

class TimeSlotStat {
  final String hhmm;
  final double vs0930Pct;
  final double vsDayMeanPct;
  final String note;

  const TimeSlotStat({
    required this.hhmm,
    required this.vs0930Pct,
    required this.vsDayMeanPct,
    this.note = '',
  });
}

class WeekdayStat {
  final int weekday;
  final String name;
  final double portfolioRelPct;
  final String summary;

  const WeekdayStat({
    required this.weekday,
    required this.name,
    required this.portfolioRelPct,
    required this.summary,
  });
}
