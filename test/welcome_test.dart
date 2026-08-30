import 'package:disaster_map/features/tutorial/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('初回の案内は3枚で、最後に地図へ進める', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(home: WelcomePage(onFinish: () => finished = true)),
    );

    // 1枚目。長い説明を並べず、見出しと数行だけにしている。
    expect(find.text('1つの地図で、日本も世界も'), findsOneWidget);
    expect(find.text('つぎへ'), findsOneWidget);

    await tester.tap(find.text('つぎへ'));
    await tester.pumpAndSettle();
    expect(find.text('見たいものだけに絞れます'), findsOneWidget);

    await tester.tap(find.text('つぎへ'));
    await tester.pumpAndSettle();
    expect(find.text('危ないときは通知で気づけます'), findsOneWidget);
    // 3枚目で終わり。ここから地図へ着地する。
    expect(find.text('つぎへ'), findsNothing);

    await tester.tap(find.text('地図をひらく'));
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('いつでもスキップできる', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(home: WelcomePage(onFinish: () => finished = true)),
    );

    await tester.tap(find.text('スキップ'));
    await tester.pump();
    expect(finished, isTrue);
  });
}
