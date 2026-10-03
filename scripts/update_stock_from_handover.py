#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""수품재고 인수인계(2026.08.31, 양다솜→이승준) PDF 기준으로 앱 재고 항목을 업데이트/추가.

출처: 한국범스카우트중앙회_재고_인수인계_20260910233713.pdf (수품재고 70종)
- 기존 품목: 수량(재고) 반영
- 대장에만 있는 품목: 신규 등록(forSale=False 인 것은 쇼핑몰 비노출=재고전용)
"""
import json
import urllib.request as rq

BASE = 'http://localhost:5071'


def _req(path, obj=None, sid='', timeout=45):
    headers = {'Content-Type': 'application/json'}
    if sid:
        headers['X-TSAK-Session'] = sid
    data = json.dumps(obj).encode() if obj is not None else None
    r = rq.Request(BASE + path, data=data, headers=headers)
    return json.loads(rq.urlopen(r, timeout=timeout).read())


def login():
    return _req('/api/login', {'tier': 'master', 'value': 'Corbuser7!@@'}, timeout=15)['sid']


# ── 1) 기존 품목 수량 업데이트 (앱 품명 → 대장 수량) ──
UPDATES = {
    '중앙회 항건 (넥커치프)': 56,          # 대장 #32 범항건
    '범중앙회 가죽 조임': 25,                # #8
    '범중앙회 칠보 조임': 99,                # #7
    '범중앙회 평생회원 흉장 (각인포함)': 11,    # #29 평생회원흉장
    '범중앙회 패치': 112,                    # #9
    '범스카우트 패치 약장': 114,             # #19 범패치약장
    '멘토 패치 약장': 45,                    # #21
    '페런츠 패치 약장': 130,                 # #20
    '멘토 금속 약장': 97,                    # #16 신형멘토금속약장
    '페런츠 금속 약장': 97,                  # #17 신형페런츠금속약장
    '범 금속 약장': 238,                     # #22
    '가죽벨트': 56,                          # #5 벨트
    '중앙회 버클': 234,                      # #25 범버클투웨이
    '범 파우치': 153,                        # #6 범주머니파우치
    '범 모자': 55,                           # #1
    '활동바지': 4,                           # #4 바지
    '범슬링': 18,                            # #18 범슬링타이
    '연간회원 뱃지': 58,                     # #14(20)+#15(38)
}

# ── 2) 대장에만 있는 품목 신규 등록 ──
# (품명, 수량, 판매가, forSale, kind(종류), size, 비고)
ADDS = [
    ('맨투맨', 31, 0, True, '의류', 'S/M/L/XL/2XL/3XL', '한치수 작게나옴 · 판매시 한치수 크게 권장'),
    ('카라티셔츠 (버건디)', 1, 17000, True, '의류', 'L', '광주연맹 사이즈 오류 물량'),
    ('티셔츠 (검정)', 1, 15000, True, '의류', 'S', '광주연맹 사이즈 오류 물량'),
    ('호랑이머리 준비 뱃지', 74, 0, True, '뱃지', '', ''),
    ('2025 연간회원 뱃지', 20, 0, True, '뱃지', '', '2025년판'),
    ('2026 연간회원 뱃지', 38, 0, True, '뱃지', '', '2026년판'),
    ('범중앙회로고 뱃지', 41, 0, False, '뱃지', '', '415호 이승준 기증 / 판매용X'),
    ('ATAS 패치', 22, 0, False, '패치', '', '75호 이항복 기증 / 판매용X'),
    ('ATAS 세잼 뱃지', 4, 0, False, '뱃지', '', '75호 이항복 기증 / 판매용X'),
    ('구형 페런츠 금속 약장', 15, 0, True, '약장', '', '구형'),
    ('구형 멘토 금속 약장', 5, 0, True, '약장', '', '구형'),
    ('구형 페런츠 메달', 74, 0, True, '메달', '', '구형'),
    ('구형 멘토 메달', 30, 0, True, '메달', '', '구형'),
    ('평생회원 조임', 58, 0, True, '조임', '', ''),
    ('감사장 약장', 48, 0, True, '약장', '', ''),
    ('감사장 메달', 98, 0, True, '메달', '', ''),
    ('범 에코백', 87, 0, True, '기념품', '', ''),
    ('범 크라프트지', 880, 0, False, '포장', '14×20:564 / 10×15:316', '활용도 — 샘플 참고'),
    ('열전사 범메달로고 (20CM)', 76, 0, False, '열전사', '20CM', ''),
    ('열전사 중앙회로고 (20CM)', 112, 0, False, '열전사', '20CM', ''),
    ('열전사 범메달로고 (5CM)', 104, 0, False, '열전사', '5CM', ''),
    ('열전사 중앙회로고 (5CM)', 101, 0, False, '열전사', '5CM', ''),
    ('열전사 범메달중앙회로고 (5CM)', 3, 0, False, '열전사', '5CM', ''),
    ('열전사 중앙회로고 불량 (5CM)', 79, 0, False, '열전사', '5CM', '불량표기물량'),
    ('열전사 범메달중앙회로고 불량 (5CM)', 78, 0, False, '열전사', '5CM', '불량표기물량'),
    ('2026 후원자 칼', 30, 0, False, '기념품', '', '2027 총회 증정 예정 · 각인 개당 3,000원'),
    ('삼색 리본', 1, 0, False, '포장', 'ROLL', ''),
    ('포장박스 (소형)', 17, 0, False, '포장', '소형', '항건 포장용'),
    ('포장박스 (대형)', 7, 0, False, '포장', '대형', '항건 포장용'),
    ('2024 VIP 패치', 10, 0, True, '패치', '', ''),
    ('2025 총회패치 SET', 7, 0, True, '패치', '', ''),
    ('2026 총회패치 SET', 2, 0, True, '패치', '', ''),
    ('2025·2026 연간회원 뱃지 SET', 4, 0, True, '뱃지', '', ''),
    ('2025 VIP 후드티', 13, 0, True, '의류', 'M', '218호 안승휘 입고 진행중'),
]


def main():
    sid = login()
    admin = _req('/api/merch/admin', sid=sid, timeout=40)
    by_name = {str(p.get('name')): p for p in admin['products']}
    print(f"현재 품목 {len(admin['products'])}종 / 제작자 {len(admin.get('makers', []))}곳")

    updated, added = 0, 0

    # 1) 수량 업데이트 (기존 필드 보존)
    for name, stk in UPDATES.items():
        p = by_name.get(name)
        if not p:
            print(f"  ⚠ 미매칭(업데이트 생략): {name}")
            continue
        payload = {
            'id': str(p.get('id', '')), 'name': name,
            'kind': str(p.get('kind', '')), 'price': int(p.get('price', 0) or 0),
            'stock': stk, 'options': p.get('options', []),
            'image': str(p.get('image', '')), 'desc': str(p.get('desc', '')),
            'size': str(p.get('size', '')), 'makerId': str(p.get('makerId', '')),
            'cost': int(p.get('cost', 0) or 0), 'madeDate': str(p.get('madeDate', '')),
            'specList': p.get('specList', []), 'quoteFile': str(p.get('quoteFile', '')),
            'quoteFileName': str(p.get('quoteFileName', '')),
            'active': p.get('active', True) is not False,
            'credentialOnly': p.get('credentialOnly') is True,
            'forSale': p.get('forSale', True) is not False,
            'soldStart': str(p.get('soldStart', '')),
            'soldBase': int(p.get('soldBase', 0) or 0),
        }
        _req('/api/merch/product', payload, sid=sid)
        updated += 1
        print(f"  ✓ 업데이트 {name}: 재고 {p.get('stock')} → {stk}")

    # 2) 신규 등록
    for name, stk, price, forSale, kind, size, note in ADDS:
        if name in by_name:
            print(f"  ⚠ 이미 존재(추가 생략): {name}")
            continue
        payload = {
            'name': name, 'kind': kind, 'price': price, 'stock': stk,
            'options': [], 'image': '', 'desc': note, 'size': size,
            'makerId': '', 'cost': 0, 'madeDate': '', 'specList': [],
            'quoteFile': '', 'quoteFileName': '', 'active': True,
            'credentialOnly': False, 'forSale': forSale,
            'soldStart': '', 'soldBase': 0,
        }
        _req('/api/merch/product', payload, sid=sid)
        added += 1
        flag = '' if forSale else ' [재고전용·판매X]'
        print(f"  + 신규 {name} (재고 {stk}){flag}")

    print(f"\n완료: 업데이트 {updated}건 · 신규 {added}건")


if __name__ == '__main__':
    main()
