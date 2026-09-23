import http.server, socketserver

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        super().end_headers()
    def __init__(self, *a, **kw):
        super().__init__(*a, directory='build/web', **kw)

with socketserver.TCPServer(('0.0.0.0', 5060), CORSRequestHandler) as httpd:
    httpd.serve_forever()
