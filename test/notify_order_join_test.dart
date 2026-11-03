// [요구 2026-11-04] 수품구매/회원가입 알림 미발생 사고 회귀 방지 테스트
//
// ## 실제 사고
//  1) "수품구매 요청이 오면 알림버튼이 오던 기능이 작동하지 않았음"
//     2026.11.02 박다운 주문 4건(261102-10:32:06-박다운-0008)이
//     notify.json 에 흔적 0건이었다. 원인: 알림 생산자 자체가 없었음.
//  2) "박다운이 회원가입한 내역도 알림이 오지 않음"
//     신규 일반회원 저장 시 approvalStatus 가 **빈 값** → _approval_of() 가
//     'approved' 로 해석 → _pending_members() 0건 → 배지·팝업 0건.
//
// ## 이 테스트의 성격
//  · 프록시(proxy_server.py)는 Dart 가 아니므로 **소스 계약(source contract)**
//    방식으로 검사한다: 파일을 읽어 필수 문자열을 단언한다.
//  · 위젯을 pump 하지 않는다 — 이 샌드박스에서 HomeScreen 은 영원히 멈춘다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _proxyPath = '/home/user/nas_proxy/proxy_server.py';

void main() {
  late String src;

  setUpAll(() {
    final f = File(_proxyPath);
    expect(f.existsSync(), isTrue, reason: '프록시 소스를 찾을 수 없다: $_proxyPath');
    src = f.readAsStringSync();
  });

  group('범용 알림 생산자(_notify_admin)', () {
    test('정의가 존재한다', () {
      expect(src.contains('def _notify_admin(type_, title, text'),
          isTrue,
          reason: '범용 알림 적재 함수가 없으면 주문/가입 알림을 만들 수 없다');
    });

    test('type/title/text/created/read 를 모두 기록한다', () {
      for (final key in ['"type"', '"title"', '"text"', '"created"', '"read"']) {
        expect(src.contains(key), isTrue, reason: '$key 필드 누락');
      }
    });

    test('최신 우선 삽입 + 200건 상한 정책을 지킨다', () {
      expect(src.contains('items.insert(0, entry)'), isTrue);
      expect(src.contains('doc["items"] = items[:200]'), isTrue);
    });
  });

  group('게시글/자료가져오기 알림은 범용 생산자로 위임', () {
    test('_board_notify 가 _notify_admin 을 호출한다', () {
      final i = src.indexOf('def _board_notify(post):');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 700);
      expect(body.contains('_notify_admin('), isTrue,
          reason: '게시글 알림이 위임 형태가 아니면 정책이 갈라진다');
    });

    test('_notify_master_import 가 _notify_admin 을 호출한다', () {
      final i = src.indexOf('def _notify_master_import(entry):');
      expect(i, greaterThan(0));
      final body = src.substring(i, i + 600);
      expect(body.contains('_notify_admin('), isTrue);
    });
  });

  group('수품구매 주문 알림', () {
    test('_merch_notify_orders 헬퍼가 존재한다', () {
      expect(src.contains('def _merch_notify_orders(orders, order_no="")'),
          isTrue);
    });

    test('type 이 order 이고 category 가 수품구매다', () {
      final i = src.indexOf('def _merch_notify_orders(orders, order_no="")');
      final body = src.substring(i, i + 2400);
      expect(body.contains('"order"'), isTrue);
      expect(body.contains('수품구매'), isTrue);
    });

    test('장바구니(배치) 주문 경로가 알림을 적재한다', () {
      expect(src.contains('_merch_notify_orders(out_orders, shared_no)'), isTrue,
          reason: '장바구니 주문은 하나의 주문번호를 공유하므로 1건으로 묶는다');
    });

    test('단일 품목 주문 경로가 알림을 적재한다', () {
      expect(src.contains('_merch_notify_orders([order])'), isTrue);
    });

    test('예약(수요조사) 접수도 알림을 남긴다', () {
      expect(src.contains('"reserve"'), isTrue);
      expect(src.contains('수품예약'), isTrue);
    });
  });

  group('회원가입 알림 + 승인 대기 전환', () {
    test('신규 일반회원은 pending 으로 시작한다', () {
      expect(src.contains('mem["approvalStatus"] = "pending"'), isTrue,
          reason: '빈 값이면 _approval_of() 가 approved 로 해석해 승인 큐에서 사라진다');
    });

    test('가입 시 approvalAt 을 반드시 채운다', () {
      expect(src.contains('mem["approvalAt"]'), isTrue,
          reason: 'approvalAt 이 비면 _approval_badge_unread 의 미확인 집계가 0 이 된다');
    });

    test('type 이 join 이고 category 가 회원가입이다', () {
      expect(src.contains('"join"'), isTrue);
      expect(src.contains('"회원가입"'), isTrue);
    });
  });

  group('notify/list 응답 계약', () {
    test('unread(워터마크) 와 readUnread(항목 read 플래그) 를 함께 준다', () {
      expect(src.contains('"readUnread": read_unread'), isTrue,
          reason: 'read 플래그를 True 로 바꾸는 코드가 없어 화면이 점을 그리면 안 꺼진다');
      expect(src.contains('"total": len(items)'), isTrue);
    });
  });

  group('Dart 클라이언트 계약', () {
    test('NasApi.notifyList 가 /api/notify/list 를 호출한다', () {
      final api = File(
              '/home/user/flutter_app/lib/services/nas_api.dart')
          .readAsStringSync();
      expect(api.contains("_uri('/api/notify/list')"), isTrue);
    });

    test('홈 화면이 응답의 unread 를 배지에 반영한다', () {
      final home = File(
              '/home/user/flutter_app/lib/screens/home_screen.dart')
          .readAsStringSync();
      expect(home.contains("r['unread']"), isTrue);
      expect(home.contains('_loadBoardUnread'), isTrue);
    });
  });
}
