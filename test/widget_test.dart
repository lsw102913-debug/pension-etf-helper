import 'package:flutter_test/flutter_test.dart';
import 'package:pension_etf_helper/main.dart';
import 'package:pension_etf_helper/models/etf_item.dart';
import 'package:pension_etf_helper/services/simulation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('6개 종목 예산(240,000원) 및 시뮬레이션 6단계 검증 테스트', () {
    final portfolio = EtfItem.defaultPortfolio();
    expect(portfolio.length, 6);

    final totalBudget = portfolio.fold<int>(0, (s, e) => s + e.budget);
    expect(totalBudget, 240000);

    for (final item in portfolio) {
      expect(item.maxQuantity, greaterThan(0));
      expect(item.totalCost, lessThanOrEqualTo(item.budget));
      expect(item.remainingBudget, greaterThanOrEqualTo(0));
    }

    final report = SimulationService.runFullSimulation(portfolio);
    expect(report.allPassed, isTrue);
    expect(report.steps.length, 6);
  });

  testWidgets('앱 UI 렌더링 및 [1/6 ~ 6/6] 연속 주문 리모컨 시뮬레이션 테스트',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PensionEtfHelperApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('연속 주문 리모컨 [1/6]'), findsOneWidget);
    expect(find.text('KODEX 미국S&P500'), findsWidgets);

    // 다음 ▶ 버튼을 5번 눌러 1/6 -> 6/6 순차 이동 검증
    for (int step = 1; step <= 5; step++) {
      await tester.tap(find.text('다음 ▶'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('연속 주문 리모컨 [${step + 1}/6]'), findsOneWidget);
    }

    expect(find.text('TIGER 미국우주테크'), findsWidgets);
  });
}
