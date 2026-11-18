import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab1_chat_ui/main.dart';

void main() {
  testWidgets('앱이 뜨고 가짜 대화가 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    // 제목
    expect(find.text('AI Chat — 실습 1 · 4'), findsOneWidget);

    // 할 일 1이 끝났다면 목록이 그려진다
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('오늘 뭐 배워?'), findsOneWidget);

    // 할 일 3이 끝났다면 입력창이 있다
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('전송하면 내 말풍선이 추가되고 입력창이 비워진다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    await tester.enterText(find.byType(TextField), '테스트 메시지');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('테스트 메시지'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );

    await finishAttempt(tester);

    // 공백만 입력하면 아무것도 추가되지 않는다
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('목록이 비면 빈 상태 문구가 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChatPage(initialMessages: [])),
    );

    expect(find.text('무엇이든 물어보세요'), findsOneWidget);

    // 첫 메시지를 보내면 빈 상태가 사라진다
    await tester.enterText(find.byType(TextField), '안녕하세요');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('무엇이든 물어보세요'), findsNothing);
    expect(find.text('안녕하세요'), findsOneWidget);
    await finishAttempt(tester);
  });

  testWidgets('키보드가 올라와도 입력창이 가려지지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatLabApp());

    // 키보드가 화면 아래 300pt(논리 픽셀)를 차지한다고 가정
    const keyboardHeight = 300.0;
    // viewInsets는 물리 픽셀 단위라서 devicePixelRatio를 곱해 준다
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardHeight * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final keyboardTop = screenHeight - keyboardHeight;

    final inputRect = tester.getRect(find.byType(TextField));
    expect(inputRect.bottom, lessThanOrEqualTo(keyboardTop));
  });

  for (final error in ['401', '500', 'Timeout']) {
    testWidgets('$error 오류를 표시하고 같은 메시지를 다시 보낸다', (tester) async {
      await tester.pumpWidget(const ChatLabApp());
      await chooseScenario(tester, '$error 오류');
      await sendMessage(tester, '재시도할 메시지');
      await finishAttempt(tester);

      expect(find.textContaining('$error ·'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '작성 중인 메시지');
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await finishAttempt(tester);

      expect(find.textContaining('$error ·'), findsNothing);
      expect(find.text('재시도할 메시지'), findsOneWidget);
      expect(find.text('메시지를 받았어요.\n“재시도할 메시지”'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '작성 중인 메시지',
      );
    });
  }

  for (final recovers in [false, true]) {
    testWidgets('429 오류는 1초와 2초를 기다린 뒤 재시도한다 (복구: $recovers)', (tester) async {
      await tester.pumpWidget(const ChatLabApp());
      await chooseScenario(tester, recovers ? '429 후 정상 응답' : '429 오류');
      await sendMessage(tester, '백오프 테스트');

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 1999));
      expect(find.text('응답을 기다리는 중…'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      await finishAttempt(tester);
      if (recovers) {
        expect(find.text('메시지를 받았어요.\n“백오프 테스트”'), findsOneWidget);
      } else {
        expect(find.textContaining('429 ·'), findsOneWidget);
        expect(find.text('다시 시도'), findsOneWidget);
      }
    });
  }

  testWidgets('오류가 난 뒤에도 새 메시지를 보낼 수 있다', (tester) async {
    await tester.pumpWidget(const ChatLabApp());
    await chooseScenario(tester, '500 오류');
    await sendMessage(tester, '실패한 메시지');
    await finishAttempt(tester);

    await chooseScenario(tester, '정상 응답');
    await sendMessage(tester, '새 메시지');
    await finishAttempt(tester);
    expect(find.textContaining('500 ·'), findsOneWidget);
    expect(find.text('메시지를 받았어요.\n“새 메시지”'), findsOneWidget);
  });
}

Future<void> chooseScenario(WidgetTester tester, String scenario) async {
  await tester.tap(find.byTooltip('응답 시나리오'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(
      of: find.text(scenario),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> sendMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
}

Future<void> finishAttempt(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}
