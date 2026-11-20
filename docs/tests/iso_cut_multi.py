#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""쓰기 중단 다점 시험 — 절단 지점을 바꿔가며 대상 파일 상태를 본다."""
import json
import os
import socket
import ssl
import sys
import time

sys.path.insert(0, "/home/user/nas_proxy")
import nas_lib

PROD_BASE = "/92_Tiger_app_data/TSAK_인가자관리"
TEST_ROOT = "/92_Tiger_app_data/_tsak_iso4_%d" % os.getpid()


def guard(p):
    if p == PROD_BASE or p.startswith(PROD_BASE + "/"):
        raise SystemExit("REFUSED: 운영 BASE 하위 금지 → " + p)


def build_body(remote_path, content, boundary):
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
    body += content + b"\r\n" + ("--%s--\r\n" % boundary).encode()
    return body


def cut_upload(cfg, remote_path, content, ratio):
    boundary = "----TSAKCUT%d" % os.getpid()
    body = build_body(remote_path, content, boundary)
    host, port = "39.123.241.4", 5001
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    raw = socket.create_connection((host, port), timeout=30)
    s = ctx.wrap_socket(raw, server_hostname=host)
    try:
        head = ("POST /webapi/entry.cgi HTTP/1.1\r\nHost: %s:%d\r\n"
                "Content-Type: multipart/form-data; boundary=%s\r\n"
                "Content-Length: %d\r\nCookie: %s\r\nConnection: close\r\n\r\n"
                % (host, port, boundary, len(body), cfg["_cookie"])).encode()
        s.sendall(head)
        n = int(len(body) * ratio)
        s.sendall(body[:n])
        time.sleep(0.2)
        return n, len(body)
    finally:
        try:
            s.close()
        except Exception:
            pass


def classify(st, OLD, NEW):
    O = len(OLD)
    N = len(NEW)
    if st is None or len(st) == 0:
        return "EMPTY_OR_MISSING"
    if len(st) == O:
        try:
            j = json.loads(st.decode("utf-8", errors="strict"))
            if j.get("v") == "OLD" and j.get("pad", "").startswith("O" * 100):
                return "OLD_INTACT"
        except Exception:
            return "OLD_SIZE_UNPARSEABLE"
        return "OLD_SIZE_OTHER"
    if len(st) == N:
        try:
            j = json.loads(st.decode("utf-8", errors="strict"))
            if j.get("v") == "NEW":
                return "NEW_INTACT"
        except Exception:
            return "NEW_SIZE_UNPARSEABLE"
        return "NEW_SIZE_OTHER"
    return "PARTIAL_%d" % len(st)


def main():
    guard(TEST_ROOT)
    cfg = json.load(open("/home/user/nas_proxy/config.json"))["nas"]
    c = nas_lib.NasClient(cfg["base"], cfg["user"], cfg["pw"])
    c.warm()
    cfg["_cookie"] = c.cookie

    OLD = json.dumps({"v": "OLD", "pad": "O" * (2 * 1024 * 1024)}).encode()
    NEW = json.dumps({"v": "NEW", "pad": "N" * (2 * 1024 * 1024)}).encode()

    results = []
    target = TEST_ROOT + "/cut.json"

    try:
        c.mkdir(os.path.dirname(TEST_ROOT), os.path.basename(TEST_ROOT))
        time.sleep(1.5)

        for ratio in (0.10, 0.40, 0.80, 0.95, 0.999):
            # 매 회 옛 내용으로 복원
            c.write(target, OLD)
            time.sleep(1.5)
            pre = c.get_info(target).get("size")

            sent, total = cut_upload(cfg, target, NEW, ratio)
            time.sleep(3.0)

            st = c.read_bytes(target)
            state = classify(st, OLD, NEW)
            row = {
                "ratio": ratio,
                "sent": sent,
                "total": total,
                "pre_size": pre,
                "post_size": len(st) if st is not None else None,
                "state": state,
            }
            results.append(row)
            print(json.dumps(row, ensure_ascii=False))
            time.sleep(1.0)

        # 마지막: 본문은 다 보내고 응답을 읽기 전에 끊기 (응답 유실)
        c.write(target, OLD)
        time.sleep(1.5)
        boundary = "----TSAKCUTRESP"
        body = build_body(target, NEW, boundary)
        host, port = "39.123.241.4", 5001
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        raw = socket.create_connection((host, port), timeout=30)
        s = ctx.wrap_socket(raw, server_hostname=host)
        head = ("POST /webapi/entry.cgi HTTP/1.1\r\nHost: %s:%d\r\n"
                "Content-Type: multipart/form-data; boundary=%s\r\n"
                "Content-Length: %d\r\nCookie: %s\r\nConnection: close\r\n\r\n"
                % (host, port, boundary, len(body), cfg["_cookie"])).encode()
        s.sendall(head)
        s.sendall(body)          # 전부 전송
        s.close()                # 응답 보기 전에 끊음
        time.sleep(4.0)
        st = c.read_bytes(target)
        results.append({
            "scenario": "response_lost_after_full_body",
            "post_size": len(st) if st is not None else None,
            "state": classify(st, OLD, NEW),
        })
        print(json.dumps(results[-1], ensure_ascii=False))

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

    with open("/tmp/iso_cut_multi.json", "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
