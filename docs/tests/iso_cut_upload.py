#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""쓰기 중단 시험 — 업로드 도중 연결을 끊으면 대상 파일이 어떻게 되는가.

허브 설계자 §2 (4속성 분리): "작성자가 한 명이어도 연결 단절·프로세스 종료·
디스크 오류는 발생할 수 있습니다." 이 주장을 실제로 확인한다.

시나리오: 3MB 파일을 multipart 로 보내다가 중간에 소켓을 닫는다.
그 뒤 대상 파일을 읽어 (a) 옛 내용 온전 (b) 새 내용 온전 (c) 잘림/손상
중 무엇인지 본다.

운영 BASE 밖 격리 폴더에서만 실행.
"""
import json
import os
import socket
import ssl
import sys
import time

sys.path.insert(0, "/home/user/nas_proxy")
import nas_lib

PROD_BASE = "/92_Tiger_app_data/TSAK_인가자관리"
TEST_ROOT = "/92_Tiger_app_data/_tsak_iso3_%d" % os.getpid()


def guard(p):
    if p == PROD_BASE or p.startswith(PROD_BASE + "/"):
        raise SystemExit("REFUSED: 운영 BASE 하위 금지 → " + p)


def partial_upload(cfg, remote_path, content, cut_bytes):
    """multipart 본문을 cut_bytes 까지만 보내고 소켓을 닫는다."""
    import urllib.parse

    boundary = "----TSAKCUT%d" % os.getpid()

    def field(name, value):
        return ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n'
                % (boundary, name, value)).encode()

    body = b""
    body += field("api", "SYNO.FileStation.Upload")
    body += field("version", "2")
    body += field("method", "upload")
    body += field("path", "/".join(remote_path.split("/")[:-1]) or "/")
    body += field("create_parents", "true")
    body += field("overwrite", "true")
    fname = remote_path.split("/")[-1]
    body += ('--%s\r\nContent-Disposition: form-data; name="file"; filename="%s"\r\n'
             'Content-Type: application/octet-stream\r\n\r\n' % (boundary, fname)).encode()
    body += content
    body += b"\r\n"
    body += ("--%s--\r\n" % boundary).encode()

    host = "39.123.241.4"
    port = 5001
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    raw = socket.create_connection((host, port), timeout=30)
    s = ctx.wrap_socket(raw, server_hostname=host)
    try:
        head = (
            "POST /webapi/entry.cgi HTTP/1.1\r\n"
            "Host: %s:%d\r\n"
            "Content-Type: multipart/form-data; boundary=%s\r\n"
            "Content-Length: %d\r\n"
            "Cookie: %s\r\n"
            "Connection: close\r\n\r\n"
            % (host, port, boundary, len(body), cfg["_cookie"])
        ).encode()
        s.sendall(head)
        # 본문의 앞부분만 보내고 끊는다
        s.sendall(body[:cut_bytes])
        time.sleep(0.3)
    finally:
        try:
            s.close()          # ← 여기서 연결 단절
        except Exception:
            pass
    return len(head) + cut_bytes, len(body)


def main():
    guard(TEST_ROOT)
    cfg = json.load(open("/home/user/nas_proxy/config.json"))["nas"]
    c = nas_lib.NasClient(cfg["base"], cfg["user"], cfg["pw"])
    c.warm()
    cfg["_cookie"] = c.cookie

    out = {}
    target = TEST_ROOT + "/cut.json"

    try:
        c.mkdir(os.path.dirname(TEST_ROOT), os.path.basename(TEST_ROOT))
        time.sleep(1.5)

        OLD = json.dumps({"v": "OLD", "pad": "O" * (3 * 1024 * 1024)}).encode()
        NEW = json.dumps({"v": "NEW", "pad": "N" * (3 * 1024 * 1024)}).encode()

        c.write(target, OLD)
        time.sleep(2.0)
        before = c.get_info(target)
        print("before size:", before.get("size"), "OLD len:", len(OLD))

        # 본문의 약 40% 만 보내고 절단
        cut = int(len(NEW) * 0.4)
        sent, total = partial_upload(cfg, target, NEW, cut)
        print("sent %d / %d bytes then closed socket" % (sent, total))

        time.sleep(3.0)   # NAS 가 정리할 시간

        # 대상 파일 상태
        st = c.read_bytes(target)
        info = c.get_info(target)
        state = "UNKNOWN"
        detail = ""
        if st is None or len(st) == 0:
            state = "EMPTY_OR_MISSING"
            detail = "len=%s" % (len(st) if st is not None else "None")
        elif len(st) == len(OLD):
            try:
                j = json.loads(st.decode("utf-8", errors="strict"))
                if j.get("v") == "OLD" and j.get("pad") == "O" * (3 * 1024 * 1024):
                    state = "OLD_INTACT"
                else:
                    state = "SAME_SIZE_DIFFERENT"
            except Exception:
                state = "SAME_SIZE_UNPARSEABLE"
        elif len(st) == len(NEW):
            try:
                j = json.loads(st.decode("utf-8", errors="strict"))
                state = "NEW_INTACT" if j.get("v") == "NEW" else "SAME_SIZE_DIFFERENT"
            except Exception:
                state = "SAME_SIZE_UNPARSEABLE"
        else:
            state = "PARTIAL_CORRUPT"
            detail = "%d bytes (OLD=%d, NEW=%d)" % (len(st), len(OLD), len(NEW))
            # 앞부분만 유효한지
            try:
                half = st.decode("utf-8", errors="strict")
                detail += " utf8_ok"
            except Exception:
                detail += " utf8_BROKEN"

        out["cut_upload"] = {
            "before_size": before.get("size"),
            "old_len": len(OLD),
            "new_len": len(NEW),
            "cut_at": cut,
            "after_size": info.get("size"),
            "bytes_readable": len(st) if st is not None else None,
            "state": state,
            "detail": detail,
        }
        print(json.dumps(out["cut_upload"], ensure_ascii=False, indent=1))

        # ── 시험 2: 같은 상황에서 서버가 살아있는가 ──────────
        alive = c.get_info(TEST_ROOT)
        out["server_alive_after_cut"] = alive.get("ok")
        print("server alive after cut:", alive.get("ok"))

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

    with open("/tmp/iso_cut_upload.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
