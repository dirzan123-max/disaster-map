import 'dart:convert';
import 'dart:io';

import 'package:disaster_map/data/sources/p2p_quake_source.dart';
import 'package:disaster_map/domain/event_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('リアルタイム監視で届く1件', () {
    /// WebSocket は、まとめて取得したときと同じ形の JSON を1件ずつ流してくる。
    final history =
        jsonDecode(File('test/fixtures/p2p_history.json').readAsStringSync())
            as List;

    test('1件ぶんの JSON を、まとめ取得と同じ形で読める', () {
      final source = P2pQuakeSource();
      final quake = history.firstWhere((entry) => entry['code'] == 551);

      final fromMessage = source.parseMessage(jsonEncode(quake));
      expect(fromMessage, hasLength(1));
      expect(fromMessage.single.kind, EventKind.earthquake);

      // まとめて取得したときと同じ結果になること
      // （どちらの経路で来ても ID が同じでないと、二重に通知が鳴る）。
      final fromHistory = source.parse(jsonEncode([quake]));
      expect(fromMessage.single.id, fromHistory.single.id);
      expect(fromMessage.single.title, fromHistory.single.title);
      expect(fromMessage.single.occurredAt, fromHistory.single.occurredAt);
    });

    test('地震・津波以外のコードは無視する', () {
      // WebSocket には利用者数の通知（555）なども流れてくる。
      final source = P2pQuakeSource();
      expect(source.parseMessage('{"code":555,"areas":[]}'), isEmpty);
      expect(source.parseMessage('{"code":561}'), isEmpty);
    });

    test('壊れた JSON では例外を投げる（呼び出し側で握りつぶす）', () {
      expect(() => P2pQuakeSource().parseMessage('{壊れて'), throwsFormatException);
    });
  });
}
