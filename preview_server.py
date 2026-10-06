#!/usr/bin/env python3
"""TSAK 웹 프리뷰 서버 — build/web 정적 서빙 + /api/* 는 로컬 프록시(5071)로 패스스루.

브라우저에서 실제 홈 화면을 그대로 렌더(헤드리스 스크린샷/수동 확인)하기 위함.
정적 파일이 존재하면 그대로 서빙, 없으면(=/api 등) 5071 프록시로 전달.
"""
import http.server
import socketserver
import urllib.request
import urllib.error
import os
import json

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')
UPSTREAM = 'http://127.0.0.1:5071'


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-TSAK-Session')
        self.send_header('Access-Control-Allow-Credentials', 'true')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def _safe_write(self, data):
        """클라이언트가 끊겨도(BrokenPipe) 서버가 죽지 않게 보호."""
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError, OSError):
            self.close_connection = True

    def handle_one_request(self):
        """연결 끊김(BrokenPipe/Reset)은 조용히 무시 — 서버 생존."""
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def handle_error(self, request, client_address):
        """예외로 스레드가 죽어도 서버(메인 루프)는 계속 돈다."""
        import sys
        et = sys.exc_info()[0]
        if et in (BrokenPipeError, ConnectionResetError):
            return

    def _is_static(self, path):
        p = path.split('?', 1)[0].lstrip('/')
        if p == '' or p == 'index.html':
            return False  # 루트도 index.html 직접 서빙 (프록시 아님)
        full = os.path.join(ROOT, p)
        return os.path.isfile(full)

    def _proxy(self, method):
        # 정적 파일 우선
        path = self.path
        p = path.split('?', 1)[0].lstrip('/')
        if p == '' or self._is_static(path):
            if p == '':
                path = '/index.html'
            self.path = path
            return super().do_GET() if method == 'GET' else super().do_POST()
        # 업스트림(5071)으로 전달
        url = UPSTREAM + path
        length = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(url, data=body, method=method)
        for h in ('Content-Type', 'X-TSAK-Session', 'Cookie', 'Accept'):
            if self.headers.get(h):
                req.add_header(h, self.headers.get(h))
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self.send_header('Content-Type', resp.headers.get('Content-Type', 'application/json'))
                self.send_header('Content-Length', str(len(data)))
                # 쿠키 전달
                sc = resp.headers.get_all('Set-Cookie') or []
                for c in sc:
                    self.send_header('Set-Cookie', c)
                self.end_headers()
                self._safe_write(data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.send_header('Content-Type', e.headers.get('Content-Type', 'application/json'))
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self._safe_write(data)
        except Exception as e:
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self._safe_write(json.dumps({'ok': False, 'err': str(e)}).encode())

    def do_GET(self):
        self._proxy('GET')

    def do_POST(self):
        self._proxy('POST')

    def do_PUT(self):
        self._proxy('PUT')

    def log_message(self, *a):
        pass


class ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    allow_reuse_port = True
    daemon_threads = True


if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5060
    with ReusableTCPServer(('0.0.0.0', port), Handler) as httpd:
        print(f'preview on 0.0.0.0:{port} (static=build/web, /api->5071)', flush=True)
        httpd.serve_forever()
