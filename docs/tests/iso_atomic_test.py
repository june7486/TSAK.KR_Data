#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""격리 원자성 시험 — 운영 BASE 밖에서만 실행한다.

허브 설계자 회신(2026-11-20) §6 요구:
  - 시험 전용 NAS 폴더를 쓴다 (운영 데이터 폴더 안에서 시험하지 않는다)
  - 시험 후 시험 프로세스만 정리한다

이 스크립트는 /92_Tiger_app_data/_tsak_iso_test_<pid> 를 만들고,
끝나면 스스로 삭제한다. 운영 BASE(/92_Tiger_app_data/TSAK_인가자관리) 는
절대 건드리지 않는다 — 시작 시 BASE 하위 경로인지 검사해서 거부한다.
"""
import json
import os
import random
import sys
import threading
import time

sys.path.insert(0, "/home/user/nas_proxy")
import nas_lib

PROD_BASE = "/92_Tiger_app_data/TSAK_인가자관리"
TEST_ROOT = "/92_Tiger_app_data/_tsak_iso_test_%d" % os.getpid()


def guard(path):
    """운영 BASE 하위면 즉시 중단."""
    if path == PROD_BASE or path.startswith(PROD_BASE + "/"):
        raise SystemExit("REFUSED: 운영 BASE 하위 경로 사용 금지 → " + path)


def main():
    guard(TEST_ROOT)
    cfg = json.load(open("/home/user/nas_proxy/config.json"))["nas"]
    c = nas_lib.NasClient(cfg["base"], cfg["user"], cfg["pw"])
    c.warm()

    results = {}

    try:
        # ── 준비 ────────────────────────────────────────────
        parent = os.path.dirname(TEST_ROOT)
        c.mkdir(parent, os.path.basename(TEST_ROOT))
        time.sleep(1.0)
        c.mkdir(TEST_ROOT, "stage")
        time.sleep(1.0)

        target = TEST_ROOT + "/live.json"
        stage_f = TEST_ROOT + "/stage/live.json"

        SMALL = json.dumps({"v": 1, "filler": "A" * 200}, ensure_ascii=False).encode()
        BIG = json.dumps({"v": 2, "filler": "B" * 400000}, ensure_ascii=False).encode()

        c.write(target, SMALL)
        time.sleep(1.0)
        print("setup: target=%d bytes" % len(SMALL))

        # ── 시험 1: 교체 중 동시 읽기 관측 ──────────────────
        # stage 에 새 내용을 올린 뒤 CopyMove 로 대상 폴더에 덮어쓴다.
        # 그 사이 리더 스레드가 계속 읽으면서 깨진 관측이 나오는지 센다.
        c.write(stage_f, BIG)
        time.sleep(1.5)

        obs = {"missing": 0, "empty": 0, "parse_error": 0, "ok_old": 0, "ok_new": 0, "other": 0}
        stop = threading.Event()
        reads = {"n": 0}

        def reader():
            while not stop.is_set():
                try:
                    raw = c.read_bytes(target)
                    reads["n"] += 1
                    if raw is None or len(raw) == 0:
                        obs["empty"] += 1
                        continue
                    try:
                        j = json.loads(raw.decode("utf-8", errors="strict"))
                    except Exception:
                        obs["parse_error"] += 1
                        continue
                    v = j.get("v")
                    if v == 1:
                        obs["ok_old"] += 1
                    elif v == 2:
                        obs["ok_new"] += 1
                    else:
                        obs["other"] += 1
                except Exception as e:
                    msg = str(e)
                    if "no such file" in msg.lower() or "does not exist" in msg.lower():
                        obs["missing"] += 1
                    else:
                        obs["other"] += 1

        # 두 개의 리더로 읽기 밀도를 높인다
        ts = [threading.Thread(target=reader, daemon=True) for _ in range(2)]
        for t in ts:
            t.start()
        time.sleep(0.8)  # 읽기 시작 확인

        # 교체 실행
        t0 = time.time()
        r = c.call({
            "api": "SYNO.FileStation.CopyMove", "version": "3", "method": "start",
            "path": json.dumps([stage_f], ensure_ascii=False),
            "dest_folder_path": TEST_ROOT,
            "overwrite": "true", "remove_src": "true",
        })
        print("copymove start:", json.dumps(r, ensure_ascii=False)[:160])

        taskid = (r.get("data") or {}).get("taskid")
        # 태스크 완료 대기
        if taskid:
            for _ in range(60):
                st = c.call({
                    "api": "SYNO.FileStation.CopyMove", "version": "3",
                    "method": "status", "taskid": taskid,
                })
                if (st.get("data") or {}).get("finished"):
                    break
                time.sleep(0.2)
        elapsed = time.time() - t0

        time.sleep(1.0)
        stop.set()
        for t in ts:
            t.join(timeout=3)

        results["test1_race"] = {
            "total_reads": reads["n"],
            "obs": obs,
            "replace_seconds": round(elapsed, 2),
        }
        print("test1 racy reads:", json.dumps(results["test1_race"], ensure_ascii=False))

        # 최종 상태 확인
        final = c.read_bytes(target)
        fj = json.loads(final.decode())
        results["test1_final"] = {"v": fj.get("v"), "len": len(final)}
        print("test1 final:", results["test1_final"])

        # stage 정리 확인
        sr = c.list(TEST_ROOT + "/stage")
        results["test1_stage_after"] = [f["name"] for f in sr.get("files", [])]
        print("test1 stage remaining:", results["test1_stage_after"])

        # ── 시험 2: Rename 덮어쓰기 거부 재확인 ─────────────
        c.write(TEST_ROOT + "/r1.txt", b"<R1>")
        c.write(TEST_ROOT + "/r2.txt", b"<R2-original>")
        time.sleep(1.0)
        rr = c.rename(TEST_ROOT + "/r1.txt", "r2.txt")
        results["test2_rename_overwrite"] = json.dumps(rr, ensure_ascii=False)[:300]
        r2 = c.read_bytes(TEST_ROOT + "/r2.txt")
        results["test2_r2_content"] = r2.decode("utf-8", errors="replace")
        print("test2 rename overwrite:", results["test2_rename_overwrite"])
        print("test2 r2 content:", results["test2_r2_content"])

        # ── 시험 3: 부분 쓰기(중단) 후 상태 ─────────────────
        # 큰 파일을 쓰는 도중 프로세스를 죽이는 대신,
        # 이미 존재하는 파일에 더 작은 내용을 덮어쓸 때
        # Upload 가 truncate 를 제대로 하는지 본다.
        c.write(TEST_ROOT + "/trunc.txt", b"X" * 50000)
        time.sleep(1.0)
        before = c.get_info(TEST_ROOT + "/trunc.txt")
        c.write(TEST_ROOT + "/trunc.txt", b"Y" * 100)
        time.sleep(1.0)
        after = c.get_info(TEST_ROOT + "/trunc.txt")
        afterb = c.read_bytes(TEST_ROOT + "/trunc.txt")
        results["test3_truncate"] = {
            "before_size": before.get("size"),
            "after_size": after.get("size"),
            "actual_bytes": len(afterb),
            "all_Y": afterb == b"Y" * 100,
        }
        print("test3 truncate:", json.dumps(results["test3_truncate"], ensure_ascii=False))

    finally:
        # ── 정리 ────────────────────────────────────────────
        try:
            guard(TEST_ROOT)
            c.delete(TEST_ROOT)
            time.sleep(1.5)
            chk = c.list(os.path.dirname(TEST_ROOT))
            left = [f["name"] for f in chk.get("files", [])
                    if os.path.basename(TEST_ROOT) in f["name"]]
            print("cleanup: remaining =", left)
        except Exception as e:
            print("cleanup error:", e)

    print("\n=== RESULTS ===")
    print(json.dumps(results, ensure_ascii=False, indent=1))
    with open("/tmp/iso_atomic_result.json", "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
