#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""현재 운영 쓰기 경로(FileStation.Upload + overwrite=true)의 원자성 시험.

운영 BASE 밖의 격리 폴더에서만 실행한다.

묻는 것: 기존 파일을 덮어쓸 때, 동시 읽기가
  (a) 옛 내용 전체  (b) 새 내용 전체  (c) 잘린/빈/깨진 내용
중 무엇을 보는가. (c) 가 한 번이라도 나오면 현재 경로는
읽기 측에서 원자적이지 않다 = 부분 상태 노출.
"""
import json
import os
import sys
import threading
import time

sys.path.insert(0, "/home/user/nas_proxy")
import nas_lib

PROD_BASE = "/92_Tiger_app_data/TSAK_인가자관리"
TEST_ROOT = "/92_Tiger_app_data/_tsak_iso2_%d" % os.getpid()


def guard(p):
    if p == PROD_BASE or p.startswith(PROD_BASE + "/"):
        raise SystemExit("REFUSED: 운영 BASE 하위 금지 → " + p)


def main():
    guard(TEST_ROOT)
    cfg = json.load(open("/home/user/nas_proxy/config.json"))["nas"]
    c = nas_lib.NasClient(cfg["base"], cfg["user"], cfg["pw"])
    c.warm()

    target = TEST_ROOT + "/live.json"
    out = {}

    try:
        c.mkdir(os.path.dirname(TEST_ROOT), os.path.basename(TEST_ROOT))
        time.sleep(1.5)

        # 실제 회원명단 크기(약 8MB)에 가까운 두 버전
        OLD = json.dumps({"v": "OLD", "pad": "O" * (3 * 1024 * 1024)}).encode()
        NEW = json.dumps({"v": "NEW", "pad": "N" * (3 * 1024 * 1024)}).encode()

        c.write(target, OLD)
        time.sleep(2.0)
        base_info = c.get_info(target)
        print("setup target size:", base_info.get("size"))

        obs = {"truncated": 0, "empty": 0, "parse_error": 0,
               "ok_old": 0, "ok_new": 0, "other": 0}
        samples = []
        stop = threading.Event()
        n_reads = {"n": 0}
        lock = threading.Lock()

        def reader(idx):
            while not stop.is_set():
                try:
                    raw = c.read_bytes(target)
                    with lock:
                        n_reads["n"] += 1
                    if raw is None or len(raw) == 0:
                        with lock:
                            obs["empty"] += 1
                            samples.append((idx, "EMPTY", 0))
                        continue
                    if len(raw) != len(OLD) and len(raw) != len(NEW):
                        with lock:
                            obs["truncated"] += 1
                            samples.append((idx, "PARTIAL", len(raw)))
                        # 내용 판별은 생략 (이미 깨짐)
                        continue
                    try:
                        j = json.loads(raw.decode("utf-8", errors="strict"))
                    except Exception:
                        with lock:
                            obs["parse_error"] += 1
                            samples.append((idx, "PARSE", len(raw)))
                        continue
                    v = j.get("v")
                    if v == "OLD":
                        with lock:
                            obs["ok_old"] += 1
                    elif v == "NEW":
                        with lock:
                            obs["ok_new"] += 1
                    else:
                        with lock:
                            obs["other"] += 1
                            samples.append((idx, "OTHER", len(raw)))
                except Exception as e:
                    msg = str(e).lower()
                    with lock:
                        if "no such file" in msg or "not exist" in msg:
                            obs["truncated"] += 1
                            samples.append((idx, "MISSING", 0))
                        else:
                            obs["other"] += 1
                            samples.append((idx, "EXC:" + str(e)[:50], 0))

        ts = [threading.Thread(target=reader, args=(i,), daemon=True) for i in range(4)]
        for t in ts:
            t.start()
        time.sleep(1.5)

        t0 = time.time()
        w = c.write(target, NEW)          # ← 운영 코드와 같은 호출
        wsec = time.time() - t0
        print("upload overwrite returned:", json.dumps(w, ensure_ascii=False)[:120],
              "in %.2fs" % wsec)

        time.sleep(1.5)
        stop.set()
        for t in ts:
            t.join(timeout=5)

        final = c.get_info(target)
        out["upload_overwrite_race"] = {
            "total_reads": n_reads["n"],
            "write_seconds": round(wsec, 2),
            "obs": obs,
            "bad_samples": samples[:10],
            "final_size": final.get("size"),
            "expected_new_size": len(NEW),
        }
        print(json.dumps(out["upload_overwrite_race"], ensure_ascii=False, indent=1))

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

    with open("/tmp/iso_upload_race.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
