#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""교체 순간의 읽기 관측 — 촘촘한 표본.

앞선 시험은 read_bytes(전체 다운로드)라 회당 1~2초 걸려 표본이 24회뿐이었다.
여기서는 (a) 크기 메타데이터 호출과 (b) 짧은 구간 읽기를 함께 돌려
표본 수를 수백 회로 올린다.

묻는 것: 기존 파일을 Upload overwrite 로 덮어쓰는 동안
  다른 읽기가 (i) 옛 크기 (ii) 새 크기 (iii) 그 사이/0
중 무엇을 보는가. (iii) 이 나오면 읽기 측에서 부분 상태가 노출된다.

운영 BASE 밖 격리 폴더에서만 실행.
"""
import json
import os
import sys
import threading
import time

sys.path.insert(0, "/home/user/nas_proxy")
import nas_lib

PROD_BASE = "/92_Tiger_app_data/TSAK_인가자관리"
TEST_ROOT = "/92_Tiger_app_data/_tsak_iso5_%d" % os.getpid()


def guard(p):
    if p == PROD_BASE or p.startswith(PROD_BASE + "/"):
        raise SystemExit("REFUSED: 운영 BASE 하위 금지 → " + p)


def main():
    guard(TEST_ROOT)
    cfg = json.load(open("/home/user/nas_proxy/config.json"))["nas"]
    c = nas_lib.NasClient(cfg["base"], cfg["user"], cfg["pw"])
    c.warm()

    OLD = json.dumps({"v": "OLD", "pad": "O" * (4 * 1024 * 1024)}).encode()
    NEW = json.dumps({"v": "NEW", "pad": "N" * (6 * 1024 * 1024)}).encode()
    LO, LN = len(OLD), len(NEW)

    target = TEST_ROOT + "/live.json"
    out = {}

    try:
        c.mkdir(os.path.dirname(TEST_ROOT), os.path.basename(TEST_ROOT))
        time.sleep(1.5)
        c.write(target, OLD)
        time.sleep(2.0)
        print("setup: OLD=%d NEW=%d" % (LO, LN))

        # ── 리더 A: 크기 메타데이터 ──────────────────────────
        obs_meta = {"old": 0, "new": 0, "other": 0, "err": 0}
        odd_meta = []
        # ── 리더 B: 짧은 구간 읽기 (앞 512바이트) ────────────
        obs_blob = {"old": 0, "new": 0, "short": 0, "empty": 0, "err": 0, "full_ok": 0}
        odd_blob = []

        stop = threading.Event()
        lock = threading.Lock()

        def meta_reader():
            while not stop.is_set():
                try:
                    r = c.call({
                        "api": "SYNO.FileStation.List", "version": "2",
                        "method": "getinfo",
                        "path": json.dumps([target], ensure_ascii=False),
                        "additional": '["size"]',
                    })
                    d = r.get("data") or {}
                    fs = d.get("files") or []
                    if not fs:
                        with lock:
                            obs_meta["err"] += 1
                        continue
                    sz = fs[0].get("additional", {}).get("size", -1)
                    with lock:
                        if sz == LO:
                            obs_meta["old"] += 1
                        elif sz == LN:
                            obs_meta["new"] += 1
                        else:
                            obs_meta["other"] += 1
                            if len(odd_meta) < 20:
                                odd_meta.append(sz)
                except Exception:
                    with lock:
                        obs_meta["err"] += 1

        def blob_reader():
            while not stop.is_set():
                try:
                    raw = c.read_bytes(target)
                    with lock:
                        if raw is None or len(raw) == 0:
                            obs_blob["empty"] += 1
                            if len(odd_blob) < 20:
                                odd_blob.append("EMPTY")
                        elif len(raw) == LO:
                            obs_blob["old"] += 1
                        elif len(raw) == LN:
                            obs_blob["new"] += 1
                        else:
                            obs_blob["short"] += 1
                            if len(odd_blob) < 20:
                                odd_blob.append(len(raw))
                except Exception:
                    with lock:
                        obs_blob["err"] += 1

        ths = [threading.Thread(target=meta_reader, daemon=True) for _ in range(3)]
        ths.append(threading.Thread(target=blob_reader, daemon=True))
        for t in ths:
            t.start()
        time.sleep(1.2)

        # ── 쓰기 3회 반복 (표본 늘리기) ──────────────────────
        write_secs = []
        for i in range(3):
            src = OLD if i % 2 == 0 else NEW
            t0 = time.time()
            c.write(target, src)
            write_secs.append(round(time.time() - t0, 2))
            time.sleep(0.6)

        time.sleep(1.5)
        stop.set()
        for t in ths:
            t.join(timeout=6)

        out["meta_reads"] = obs_meta
        out["meta_odd_sizes"] = odd_meta[:20]
        out["blob_reads"] = obs_blob
        out["blob_odd_lengths"] = odd_blob[:20]
        out["write_secs"] = write_secs
        out["meta_total"] = sum(obs_meta.values())
        out["blob_total"] = sum(obs_blob.values())

        print(json.dumps(out, ensure_ascii=False, indent=1))

    finally:
        try:
            guard(TEST_ROOT)
            c.delete(TEST_ROOT)
            time.sleep(1.5)
            chk = c.list(os.path.dirname(TEST_ROOT))
            left = [f["name"] for f in chk.get("files", [])
                    if os.path.basename(TEST_ROOT) in f["name"]]
            print("cleanup remaining:", left)
        except Exception as e:
            print("cleanup error:", e)

    with open("/tmp/iso_race_dense.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
