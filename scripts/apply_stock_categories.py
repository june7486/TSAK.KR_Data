#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""수품재고 구분(카테고리)·누락품목 + 비품재고 정정 — 인수인계 PDF(2026.08.31) 기준.

① 수품재고: PDF 4구분(의류·착용류 / 배지·패치·조임류 / 약장·메달·기념품 /
   기타·열전사·포장)을 상품에 반영 + 미등록 품목(#43~55) 추가.
② 비품재고: PDF 08페이지(중앙회물품 25종)와 대조 — 오타 품명/비고 정정.
"""
import json
import urllib.request as rq

BASE = 'http://localhost:5071'


def _req(path, obj=None, sid='', timeout=45):
    h = {'Content-Type': 'application/json'}
    if sid:
        h['X-TSAK-Session'] = sid
    data = json.dumps(obj).encode() if obj is not None else None
    return json.loads(rq.urlopen(rq.Request(BASE + path, data=data, headers=h),
                                 timeout=timeout).read())


def login():
    return _req('/api/login', {'tier': 'master', 'value': 'Corbuser7!@@'},
                timeout=15)['sid']


# ── ① 수품 구분 매핑 (앱 품명 → PDF 4구분) ──
C_APPAREL = '의류·착용류'
C_BADGE = '배지·패치·조임류'
C_MEDAL = '약장·메달·기념품'
C_ETC = '기타·열전사·포장'
C_SET = '세트·멤버십'

CAT = {
    '신규 인가자 세트': C_SET, '평생회원 세트': C_SET,
    '중앙회 항건 (넥커치프)': C_APPAREL,
    '범 모자': C_APPAREL, '맨투맨': C_APPAREL,
    '카라티셔츠 (버건디)': C_APPAREL, '티셔츠 (검정)': C_APPAREL,
    '활동바지': C_APPAREL, '가죽벨트': C_APPAREL, '2025 VIP 후드티': C_APPAREL,
    '범 파우치': C_BADGE, '범중앙회 칠보 조임': C_BADGE,
    '범중앙회 가죽 조임': C_BADGE, '범중앙회 패치': C_BADGE,
    '호랑이머리 준비 뱃지': C_BADGE, '범중앙회로고 뱃지': C_BADGE,
    'ATAS 패치': C_BADGE, 'ATAS 세잼 뱃지': C_BADGE,
    '연간회원 뱃지': C_BADGE, '2025 연간회원 뱃지': C_BADGE,
    '2026 연간회원 뱃지': C_BADGE, '멘토 금속 약장': C_BADGE,
    '페런츠 금속 약장': C_BADGE, '범슬링': C_BADGE,
    '범스카우트 패치 약장': C_MEDAL, '페런츠 패치 약장': C_MEDAL,
    '멘토 패치 약장': C_MEDAL, '범 금속 약장': C_MEDAL,
    '구형 페런츠 금속 약장': C_MEDAL, '구형 멘토 금속 약장': C_MEDAL,
    '중앙회 버클': C_MEDAL, '구형 페런츠 메달': C_MEDAL,
    '구형 멘토 메달': C_MEDAL, '평생회원 조임': C_MEDAL,
    '범중앙회 평생회원 흉장 (각인포함)': C_MEDAL,
    '감사장 약장': C_MEDAL, '감사장 메달': C_MEDAL, '범 에코백': C_MEDAL,
    '멘토 메달 (각인포함)': C_MEDAL, '페런츠 메달 (각인포함)': C_MEDAL,
    '범 크라프트지': C_ETC, '열전사 범메달로고 (20CM)': C_ETC,
    '열전사 중앙회로고 (20CM)': C_ETC, '열전사 범메달로고 (5CM)': C_ETC,
    '열전사 중앙회로고 (5CM)': C_ETC, '열전사 범메달중앙회로고 (5CM)': C_ETC,
    '열전사 중앙회로고 불량 (5CM)': C_ETC,
    '열전사 범메달중앙회로고 불량 (5CM)': C_ETC,
    '2026 후원자 칼': C_ETC, '삼색 리본': C_ETC,
    '포장박스 (소형)': C_ETC, '포장박스 (대형)': C_ETC,
    '2024 VIP 패치': C_ETC, '2025 총회패치 SET': C_ETC,
    '2026 총회패치 SET': C_ETC, '2025·2026 연간회원 뱃지 SET': C_ETC,
}

# 미등록 품목 추가(#43~55) — (품명, 구분, 수량, forSale, 비고)
ADD_ITEMS = [
    ('신형 멘토메달', C_MEDAL, 0, True, '218호 안승휘 입고 진행중 — 수량 확정 전'),
    ('각종 메달 핀 교체용', C_MEDAL, 0, False, '색상별 멘토·페런츠·감사장 교체 배송 · 고무버클 클레임 많음'),
    ('스티커 3종', C_ETC, 0, False, '1988로고·범중앙회로고·범메달로고 — 2024년 제작'),
    ('투명 스티커 (액자 부착용)', C_ETC, 0, False, '액자 부착용'),
    ('수품 배송용 포장봉투', C_ETC, 0, False, ''),
]

# ── ② 비품재고 정정 (현재 품명 → 새 이름, 새 비고) ──
SUP_FIX = {
    '롤맨텐트': ('콜맨 텐트', '1동 불량 — 끈으로 표기 / 사유 메모지에 기입'),
    '롤맨 타프': ('콜맨 타프', ''),
    '롤맨 2구 버너': ('콜맨 2구 버너', '정상작동'),
    '스크린타프': ('스크린타프', '1개 불량 — 끈으로 표기 / 사유 메모지에 기입'),
    '3구 멀티탭': ('3구 멀티탭', '2026 잼버리 과정활동'),
    '안전고글': ('안전고글', '2026 잼버리 과정활동'),
    '망치': ('망치', '2026 잼버리 과정활동'),
    '등산스틱': ('등산스틱', '2026 잼버리 과정활동'),
    '아이스박스': ('아이스박스', '311호 이종학 기증 (기증품)'),
    '사무용품': ('사무용품', '볼펜·매직·가위·칼 등'),
    '충회 장식용 3색 현수막': ('총회 장식용 3색 현수막', '파랑 2 / 흰색 2 / 빨강 2'),
    '재회횟사 배너 거치대 SET': ('재회행사 배너 거치대 SET', ''),
    '중앙회 헹사 기': ('중앙회 행사기', ''),
    '접이식 돌탑 박스': ('접이식 폴딩박스', '수품 정리용'),
    '팩': ('팩', '새제품 97 / 사용중 10 / 불량 32'),
    '감사장 액자 SAMPLE': ('감사장 액자 SAMPLE', ''),
}


def main():
    sid = login()
    adm = _req('/api/merch/admin', sid=sid, timeout=40)
    prods = adm['products']

    # ① 카테고리 반영 + 누락 추가
    cat_done, add_done = 0, 0
    by_name = {str(p.get('name')): p for p in prods}
    for p in prods:
        nm = str(p.get('name'))
        want = CAT.get(nm, '')
        if want and str(p.get('category', '')) != want:
            _req('/api/merch/product', _product_payload(p, category=want), sid=sid)
            cat_done += 1
    for name, cat, qty, forSale, note in ADD_ITEMS:
        if name in by_name:
            continue
        _req('/api/merch/product', {
            'name': name, 'kind': cat, 'category': cat, 'price': 0, 'stock': qty,
            'options': [], 'image': '', 'desc': note, 'size': '', 'makerId': '',
            'cost': 0, 'madeDate': '', 'specList': [], 'quoteFile': '',
            'quoteFileName': '', 'active': True, 'credentialOnly': False,
            'forSale': forSale, 'soldStart': '', 'soldBase': 0,
        }, sid=sid)
        add_done += 1
        print(f"  + 수품추가 {name} [{cat}]" + ('' if forSale else ' (판매X)'))

    # ② 비품재고 정정
    sup = adm.get('supplies', [])
    sup_done = 0
    for s in sup:
        nm = str(s.get('name'))
        if nm in SUP_FIX:
            new_name, new_note = SUP_FIX[nm]
            _req('/api/merch/supplies', {
                'id': str(s.get('id')), 'name': new_name,
                'qty': int(s.get('qty', 0) or 0), 'note': new_note,
            }, sid=sid)
            sup_done += 1
            if new_name != nm:
                print(f"  ✓ 비품 정정 {nm} → {new_name}")

    print(f"\n완료: 수품 구분반영 {cat_done}건 · 수품 추가 {add_done}건 · 비품 정정 {sup_done}건")


def _product_payload(p, **over):
    base = {
        'id': str(p.get('id', '')), 'name': str(p.get('name', '')),
        'kind': str(p.get('kind', '')), 'category': str(p.get('category', '')),
        'price': int(p.get('price', 0) or 0), 'stock': int(p.get('stock', 0) or 0),
        'options': p.get('options', []), 'image': str(p.get('image', '')),
        'desc': str(p.get('desc', '')), 'size': str(p.get('size', '')),
        'makerId': str(p.get('makerId', '')), 'cost': int(p.get('cost', 0) or 0),
        'madeDate': str(p.get('madeDate', '')), 'specList': p.get('specList', []),
        'quoteFile': str(p.get('quoteFile', '')),
        'quoteFileName': str(p.get('quoteFileName', '')),
        'active': p.get('active', True) is not False,
        'credentialOnly': p.get('credentialOnly') is True,
        'forSale': p.get('forSale', True) is not False,
        'soldStart': str(p.get('soldStart', '')),
        'soldBase': int(p.get('soldBase', 0) or 0),
    }
    base.update(over)
    return base


if __name__ == '__main__':
    main()
