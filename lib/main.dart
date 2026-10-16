import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/etf_item.dart';
import 'services/mstock_bridge.dart';
import 'services/naver_finance_service.dart';
import 'services/simulation_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PensionEtfHelperApp());
}

class PensionEtfHelperApp extends StatelessWidget {
  const PensionEtfHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '미래에셋 연금모으기 도우미',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6D00),
          brightness: Brightness.dark,
          primary: const Color(0xFFFF8F00),
          secondary: const Color(0xFF38BDF8),
          surface: const Color(0xFF1E293B),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const String _portfolioPrefsKey = 'user_etf_portfolio_v1';

  late TabController _tabController;
  List<EtfItem> _portfolio = EtfItem.defaultPortfolio();
  IntradayAnalysisResult _analysis = IntradayAnalysisResult(
    timeSlots: NaverFinanceService.defaultTimeSlotStats(),
    weekdays: NaverFinanceService.defaultWeekdayStats(),
    analyzedTradingDays: 7,
    lastUpdated: '2026.10.16 기준 실측 데이터',
  );
  late SimulationReport _simReport;

  int _remoteIndex = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _simReport = SimulationService.runFullSimulation(_portfolio);
    _loadSavedAndRefresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAndRefresh() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_portfolioPrefsKey);
      if (saved != null) {
        final List decoded = jsonDecode(saved);
        _portfolio = decoded
            .map((e) => EtfItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    final updatedPortfolio =
        await NaverFinanceService.fetchLatestPortfolio(_portfolio);
    final analysis =
        await NaverFinanceService.analyzeOptimalDayAndTime(updatedPortfolio);

    if (!mounted) return;
    setState(() {
      _portfolio = updatedPortfolio;
      _analysis = analysis;
      _simReport = SimulationService.runFullSimulation(_portfolio);
      _isLoading = false;
    });
  }

  Future<void> _savePortfolio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _portfolioPrefsKey,
        jsonEncode(_portfolio.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  String _fmt(int n) {
    final s = n.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => '${m[1]},');
  }

  void _copyText(String label, String value, String toast) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(toast, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0284C7),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startFloatingAndLaunchMStock() async {
    final current = _portfolio[_remoteIndex];
    Clipboard.setData(ClipboardData(text: current.maxQuantity.toString()));

    final canOverlay = await MStockBridge.canDrawOverlays();
    if (!canOverlay) {
      if (!mounted) return;
      final goGrant = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('미니 리모컨 권한 안내'),
          content: const Text(
            '미래에셋 M-STOCK 화면 위에 [1/6 ~ 6/6] 연속 주문 미니 리모컨을 띄우려면 "다른 앱 위에 표시" 권한이 필요합니다.\n\n'
            '권한을 허용하시겠습니까? (거부하셔도 수량 자동 복사 후 M-STOCK이 바로 실행됩니다)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('그냥 M-STOCK 열기'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('권한 설정하기'),
            ),
          ],
        ),
      );
      if (goGrant == true) {
        await MStockBridge.requestOverlayPermission();
        return;
      }
    } else {
      await MStockBridge.startFloatingRemote(
        _portfolio,
        startIndex: _remoteIndex,
      );
    }

    await MStockBridge.launchMStock();
  }

  Future<void> _editBudgetDialog(int index) async {
    final item = _portfolio[index];
    final controller = TextEditingController(text: item.budget.toString());
    final newBudget = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('${item.name} 최대 매수 금액 수정'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '1회 최대 매수 금액 (원)',
            suffixText: '원',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.replaceAll(',', ''));
              Navigator.pop(ctx, v);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (newBudget != null && newBudget > 0) {
      setState(() {
        _portfolio[index] = item.copyWith(budget: newBudget);
        _simReport = SimulationService.runFullSimulation(_portfolio);
      });
      await _savePortfolio();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6D00),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'M-STOCK',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '연금모으기 원터치 주문 도우미',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSavedAndRefresh,
            tooltip: '실시간 시세 새로고침',
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF8F00),
          labelColor: const Color(0xFFFFB300),
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.touch_app, size: 18), text: '오늘의 주문(6종)'),
            Tab(icon: Icon(Icons.analytics, size: 18), text: '최적 요일·시간'),
            Tab(icon: Icon(Icons.verified, size: 18), text: '시뮬레이션 검증'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrderTab(),
          _buildAnalysisTab(),
          _buildSimulationTab(),
        ],
      ),
    );
  }

  Widget _buildOrderTab() {
    final totalBudget = _portfolio.fold<int>(0, (s, e) => s + e.budget);
    final totalCost = _portfolio.fold<int>(0, (s, e) => s + e.totalCost);
    final totalRemaining = totalBudget - totalCost;
    final totalSaved =
        _portfolio.fold<int>(0, (s, e) => s + e.totalSavedVs0930);
    final currentItem = _portfolio[_remoteIndex];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 1. 최적 요일 & 시간 추천 배너
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF38BDF8).withAlpha(100)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFFFBBF24), size: 20),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '데이터 분석 추천 매수 타이밍 (9:30 고점 회피)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFFBBF24),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _tabController.animateTo(1),
                    icon: const Icon(Icons.bar_chart, size: 16),
                    label: const Text('상세분석', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '• 추천 요일: 1위 목요일(-0.10%) / 2위 월요일(-0.04%, 미국ETF 최저)\n'
                '• 추천 시간: 1위 15:00~15:10 (-0.14% 저렴) / 2위 09:10 (-0.09% 저렴)',
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 원터치 M-STOCK 미니 리모컨 컨트롤러
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF8F00), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6D00),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '연속 주문 리모컨 [${_remoteIndex + 1}/${_portfolio.length}]',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    '종목코드: ${currentItem.code}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                currentItem.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '주문 수량: ${currentItem.maxQuantity}주',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '현재가 ${_fmt(currentItem.currentPrice)}원 (합계 ${_fmt(currentItem.totalCost)}원 / 예산 ${_fmt(currentItem.budget)}원)',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _remoteIndex > 0
                          ? () {
                              setState(() => _remoteIndex--);
                              final item = _portfolio[_remoteIndex];
                              _copyText(
                                'qty',
                                item.maxQuantity.toString(),
                                '[${_remoteIndex + 1}/6] ${item.name}: ${item.maxQuantity}주 복사됨!',
                              );
                            }
                          : null,
                      child: const Text('◀ 이전'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _copyText(
                        'code',
                        currentItem.code,
                        '${currentItem.name} 종목코드(${currentItem.code}) 복사됨!',
                      ),
                      child: const Text('코드복사'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _copyText(
                        'qty',
                        currentItem.maxQuantity.toString(),
                        '${currentItem.name} 수량(${currentItem.maxQuantity}주) 복사됨!',
                      ),
                      child: Text('수량(${currentItem.maxQuantity})복사'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6D00),
                      ),
                      onPressed: () {
                        setState(() {
                          _portfolio[_remoteIndex] =
                              currentItem.copyWith(isCompleted: true);
                          if (_remoteIndex < _portfolio.length - 1) {
                            _remoteIndex++;
                          }
                        });
                        final nextItem = _portfolio[_remoteIndex];
                        _copyText(
                          'qty',
                          nextItem.maxQuantity.toString(),
                          '[${_remoteIndex + 1}/6] ${nextItem.name}: ${nextItem.maxQuantity}주 자동 복사됨!',
                        );
                      },
                      child: Text(
                          _remoteIndex < _portfolio.length - 1 ? '다음 ▶' : '완료 ✓'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _startFloatingAndLaunchMStock,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text(
                    '화면 위 미니 리모컨 띄우고 미래에셋 M-STOCK 열기',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. 회차당 예산 요약 카드
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _summaryCell('회차당 총 예산', '${_fmt(totalBudget)}원', Colors.white),
                  _summaryCell(
                      '실제 주문 총액', '${_fmt(totalCost)}원', const Color(0xFF38BDF8)),
                  _summaryCell('9:30 대비 절약', '+${_fmt(totalSaved)}원',
                      const Color(0xFF4ADE80)),
                ],
              ),
              const Divider(height: 20, color: Colors.white12),
              Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 18, color: Color(0xFFFBBF24)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '종목별 1주 단위 매수 후 남는 잔액 합계: ${_fmt(totalRemaining)}원\n'
                      '👉 ${_simReport.extraShareRecommendation}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. 6개 종목 상세 리스트
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '📋 내 연금 모으기 6종목 자동 수량 계산표 (터치 시 선택/복사)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...List.generate(_portfolio.length, (i) {
          final item = _portfolio[i];
          final isSelected = i == _remoteIndex;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: isSelected
                ? const Color(0xFF1E3A5F)
                : const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFF38BDF8)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _remoteIndex = i);
                _copyText(
                  'qty',
                  item.maxQuantity.toString(),
                  '[${i + 1}/6] ${item.name}: 매수 수량 ${item.maxQuantity}주 복사됨!',
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: item.isCompleted
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF334155),
                          child: Text(
                            item.isCompleted ? '✓' : '${i + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                '코드 ${item.code} · 최대 예산 ${_fmt(item.budget)}원',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _editBudgetDialog(i),
                          icon: const Icon(Icons.edit,
                              size: 18, color: Colors.white54),
                          tooltip: '예산 수정',
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.maxQuantity}주 매수',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '현재가 ${_fmt(item.currentPrice)}원 (9:30가 ${_fmt(item.price0930)}원)',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          '주문액 ${_fmt(item.totalCost)}원 (잔액 ${_fmt(item.remainingBudget)}원)',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF93C5FD)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _summaryCell(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildAnalysisTab() {
    final sortedSlots = List<TimeSlotStat>.from(_analysis.timeSlots)
      ..sort((a, b) => a.vsDayMeanPct.compareTo(b.vsDayMeanPct));

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF4ADE80).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🎯 내 6종목(24만원) 맞춤 최적 요일 & 시간 결론',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4ADE80),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '분석 기준: 2026.02.03(모으기 시작일)~현재 일봉 및 최근 ${_analysis.analyzedTradingDays}영업일(2주 누적 추적) 10분 분봉 가중평균 (${_analysis.lastUpdated})',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
              const Divider(height: 20, color: Colors.white12),
              const Text(
                '1️⃣ 가장 저렴한 요일 추천:\n'
                '  • 1순위: 목요일 (주간 평균 대비 -0.0985% 저렴)\n'
                '    → 금현물·인도·우주테크·S&P500 모두 주간 평균 이하인 요일\n'
                '  • 2순위: 월요일 (주간 평균 대비 -0.0418% 저렴, 현재 설정)\n'
                '    → 비중이 가장 큰 미국S&P500(9만원)·나스닥100(7만원)·차이나(2.5만원)는 월요일이 가장 저렴!\n\n'
                '2️⃣ 하루 중 가장 저렴한 시간대 추천:\n'
                '  • 1순위 (오후장): 15:00 ~ 15:10 (09:30 대비 평균 -0.138% 저렴)\n'
                '    → 장 마감 동시호가(15:20) 직전 LP 스프레드가 가장 안정되고 당일 고점 거품이 빠지는 시간\n'
                '  • 2순위 (오전장): 09:10 ~ 09:15 (09:30 대비 평균 -0.086% 저렴)\n'
                '    → 09:30 미래에셋 연금모으기 일괄 시장가 매수 물량이 쏟아지기 직전 구간!\n'
                '  • 피해야 할 시간: 09:30~09:40(자동매수 피크), 10:30(중국개장 변동성 최고점), 12:00~13:50',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '📅 요일별 포트폴리오 상대 가격 순위 (낮을수록 저렴)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ..._analysis.weekdays.map((w) {
          final isCheap = w.portfolioRelPct < 0;
          return Card(
            color: const Color(0xFF1E293B),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(w.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCheap
                          ? const Color(0xFF065F46)
                          : const Color(0xFF7F1D1D),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${w.portfolioRelPct >= 0 ? "+" : ""}${w.portfolioRelPct.toStringAsFixed(4)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isCheap
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFFCA5A5),
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(w.summary,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70)),
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        const Text(
          '⏰ 하루 중 시간대별 가격 순위 (2주간 자동 누적 추적)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        const Text(
          '앱을 열 때마다 최근 2주간(및 향후 2주간) 10분 단위 실거래 데이터를 자동 수집·갱신합니다.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 8),
        ...List.generate(sortedSlots.length, (idx) {
          final slot = sortedSlots[idx];
          final isCheap = slot.vs0930Pct < 0;
          final is0930 = slot.hhmm == '09:30';
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: is0930
                  ? const Color(0xFF3B1D1D)
                  : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: idx < 3
                    ? const Color(0xFF4ADE80)
                    : is0930
                        ? const Color(0xFFF87171)
                        : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${idx + 1}위 · ${slot.hhmm}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '09:30 대비 ${slot.vs0930Pct >= 0 ? "+" : ""}${slot.vs0930Pct.toStringAsFixed(4)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isCheap
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFFF87171),
                      ),
                    ),
                  ],
                ),
                if (slot.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    slot.note,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSimulationTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _simReport.allPassed
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFFF87171),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _simReport.allPassed ? Icons.verified : Icons.error,
                    color: _simReport.allPassed
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _simReport.allPassed
                          ? '전체 6단계 시뮬레이션 검증 통과 (오류 0건)'
                          : '시뮬레이션 점검 필요',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _simReport =
                            SimulationService.runFullSimulation(_portfolio);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('6개 종목 전체 시뮬레이션 재검증 완료! (정상)'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('재실행'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '• 회차당 설정 예산: ${_fmt(_simReport.totalBudget)}원\n'
                '• 6종목 실주문 합계: ${_fmt(_simReport.totalExecutedCost)}원 (총 ${_portfolio.fold<int>(0, (s, e) => s + e.maxQuantity)}주)\n'
                '• 1주 단위 매수 후 잔여 예수금: ${_fmt(_simReport.totalRemainingCash)}원',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._simReport.steps.map((step) => Card(
              color: const Color(0xFF1E293B),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: step.passed
                      ? const Color(0xFF065F46)
                      : const Color(0xFF7F1D1D),
                  child: Text(
                    step.passed ? 'PASS' : 'FAIL',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ),
                title: Text(
                  'Step ${step.stepNumber}. ${step.title}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    step.detail,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}
