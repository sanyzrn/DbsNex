import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/chat_history.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  for (final language in ['en', 'fa']) {
    for (final dark in [false, true]) {
      testWidgets(
        '$language dark=$dark history groups, previews and deletes safely',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          ChatHistory.storageDirectory = null;
          final now = DateTime.now();
          ChatThread thread(String id, DateTime at) => ChatThread(
            id: id,
            updatedAt: at,
            messages: [
              ChatMessage(
                role: ChatRole.user,
                content: language == 'fa'
                    ? 'گفت‌وگو $id درباره ایده‌های تازه و برنامه‌های آینده'
                    : 'Conversation $id about new ideas and future plans',
              ),
              const ChatMessage(
                role: ChatRole.assistant,
                content: '**Last reply** with useful details.',
              ),
            ],
          );
          SharedPreferences.setMockInitialValues({
            'ai.chatThreads': jsonEncode([
              thread('today', now).toJson(),
              thread(
                'yesterday',
                DateTime(now.year, now.month, now.day - 1, 8),
              ).toJson(),
              thread(
                'older',
                DateTime(now.year, now.month, now.day - 10, 8),
              ).toJson(),
            ]),
          });
          final history = ChatHistory(await SharedPreferences.getInstance());
          addTearDown(history.dispose);
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              theme: dark ? nexDarkTheme() : nexLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.8)),
                child: child!,
              ),
              home: Scaffold(
                body: ChatHistorySheet(
                  history: history,
                  activeThreadId: 'today',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(ChatHistorySheet)),
          );
          expect(find.text(l.chatHistory), findsOneWidget);
          expect(find.text(l.timelineGroupToday), findsOneWidget);
          expect(find.textContaining('Last reply'), findsWidgets);
          final row = find.byKey(const ValueKey('history-thread-today'));
          final menu = find.descendant(
            of: row,
            matching: find.byType(NexPopupMenuButton<String>),
          );
          expect(tester.getSize(menu).shortestSide, greaterThanOrEqualTo(48));
          expect(history.threads, hasLength(3));
          await tester.tap(menu);
          await tester.pumpAndSettle();
          expect(
            history.threads,
            hasLength(3),
            reason: 'opening the menu never deletes a conversation',
          );
          await tester.tap(find.text(l.delete));
          await tester.pumpAndSettle();
          expect(history.threads.map((t) => t.id), ['yesterday', 'older']);
          expect(row, findsNothing);
          expect(find.text(l.timelineGroupToday), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
