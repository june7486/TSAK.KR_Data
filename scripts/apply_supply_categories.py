#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""비품재고(중앙회물품 25종) 구분(카테고리) 반영 — 인수인계 PDF 08페이지 분류 기준.

PDF 원문 분류: "잼버리 과정활동장비 · 사무용품 · 행사배너 · 액자 · 폴딩박스 등"
 → 7구분으로 정리해 각 비품에 category 부여(부분 병합 업데이트라 qty/note/name 보존).
"""
import json
import urllib.request as rq

BASE = 'http://localhost:5071'

C_JAM = '잼버리 과정활동'
C_CAMP = '야영·장비'
C_EVENT = '행사·의전'
C_OFFICE = '사무용품'
C_FRAME = '액자·기념'
C_BANNER = '배너·현수막'
C_PACK = '포장·정리'

CAT = {
    '3구 멀티탭': C_JAM,
    '안전고글': C_JAM,
    '망치': C_JAM,
    '등산스틱': C_JAM,
    '콜맨 텐트': C_CAMP,
    '콜맨 타프': C_CAMP,
    '스크린타프': C_CAMP,
    '콜맨 2구 버너': C_CAMP,
    '팩': C_CAMP,
    '비상담요': C_EVENT,
    '의사봉': C_EVENT,
    '경품추첨함': C_EVENT,
    '쟁반 대형': C_EVENT,
    '쟁반 소형': C_EVENT,
    '아이스박스': C_EVENT,
    '부고기': C_EVENT,
    '중앙회 행사기': C_EVENT,
    '사무용품': C_OFFICE,
    '감사장 액자 SAMPLE': C_FRAME,
    '다용도 액자': C_FRAME,
    '총회 장식용 3색 현수막': C_BANNER,
    '배너거치대': C_BANNER,
    '재회행사 배너 거치대 SET': C_BANNER,
    'ATAS 가입안내 배너 거치대 SET': C_BANNER,
    '접이식 폴딩박스': C_PACK,
}


def _req(path, obj=None, sid='', timeout=45):
    h = {'Content-Type': 'application/json'}
    if sid:
        h['X-TSAK-Session'] = sid
    data = json.dumps(obj).encode() if obj is not None else None
    return json.loads(rq.urlopen(rq.Request(BASE + path, data=data, headers=h),
                                 timeout=timeout).read())


def main():
    sid = _req('/api/login', {'tier': 'master', 'value': 'Corbuser7!@@'},
               timeout=15)['sid']
    adm = _req('/api/merch/admin', sid=sid, timeout=40)
    sup = adm.get('supplies', [])
    done, miss = 0, []
    for s in sup:
        nm = str(s.get('name'))
        want = CAT.get(nm)
        if want and str(s.get('category', '')) != want:
            _req('/api/merch/supplies', {
                'id': str(s.get('id')), 'category': want,
            }, sid=sid)
            done += 1
            print(f"  ✓ {nm} → [{want}]")
        elif not want:
            miss.append(nm)
    print(f"\n완료: 비품 구분반영 {done}건")
    if miss:
        print('구분 미지정(확인 필요):', miss)


if __name__ == '__main__':
    main()
