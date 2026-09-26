"""Synology DSM FileStation API 클라이언트 (쿠키 세션 방식)"""
import urllib.request, urllib.parse, ssl, json

class NasClient:
    def __init__(self, base, user, pw):
        self.base = base.rstrip('/')
        self.user = user
        self.pw = pw
        self.ctx = ssl.create_default_context()
        self.ctx.check_hostname = False
        self.ctx.verify_mode = ssl.CERT_NONE
        self.cookie = None

    def _login(self):
        p = {"api":"SYNO.API.Auth","version":"6","method":"login",
             "account":self.user,"passwd":self.pw,"session":"FileStation","format":"cookie"}
        data = urllib.parse.urlencode(p).encode()
        req = urllib.request.Request(self.base+"/webapi/entry.cgi", data=data)
        with urllib.request.urlopen(req, context=self.ctx, timeout=25) as r:
            sc = r.headers.get_all("Set-Cookie") or []
            j = json.loads(r.read().decode())
        if not j.get("success"):
            raise RuntimeError("NAS login failed: %s" % j)
        self.cookie = "; ".join([c.split(";")[0] for c in sc])
        return j

    def call(self, params, retry=True):
        if not self.cookie:
            self._login()
        data = urllib.parse.urlencode(params).encode()
        req = urllib.request.Request(self.base+"/webapi/entry.cgi", data=data)
        req.add_header("Cookie", self.cookie)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=60) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            if retry:
                self.cookie = None
                self._login()
                return self.call(params, retry=False)
            raise

    # --- high level ---
    def list(self, path):
        r = self.call({"api":"SYNO.FileStation.List","version":"2","method":"list",
                       "folder_path":path, "additional":'["real_path","size","type","perm"]'})
        if not r.get("success"):
            return {"ok": False, "error": r}
        return {"ok": True, "files": [
            {"name":f["name"], "isdir":f.get("isdir",False),
             "size":f.get("additional",{}).get("size",0),
             "path":f.get("path","")} for f in r["data"]["files"]]}

    def read_bytes(self, path):
        if not self.cookie: self._login()
        p = {"api":"SYNO.FileStation.Download","version":"2","method":"download",
             "path":'["%s"]' % path, "mode":"open"}
        data = urllib.parse.urlencode(p).encode()
        req = urllib.request.Request(self.base+"/webapi/entry.cgi", data=data)
        req.add_header("Cookie", self.cookie)
        with urllib.request.urlopen(req, context=self.ctx, timeout=120) as r:
            return r.read()

    def read(self, path):
        return self.read_bytes(path).decode("utf-8", errors="replace")

    def write(self, path, content_bytes):
        boundary = "----TSAKBOUNDARY7d01"
        # multipart with fields + file
        def field(name, value):
            return (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n").encode()
        body = b""
        body += field("api","SYNO.FileStation.Upload")
        body += field("version","2")
        body += field("method","upload")
        body += field("path","/".join(path.split("/")[:-1]) or "/")
        body += field("create_parents","true")
        body += field("overwrite","true")
        fname = path.split("/")[-1]
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{fname}\"\r\n"
                 f"Content-Type: application/octet-stream\r\n\r\n").encode()
        body += content_bytes
        body += b"\r\n"
        body += f"--{boundary}--\r\n".encode()
        if not self.cookie: self._login()
        req = urllib.request.Request(self.base+"/webapi/entry.cgi", data=body)
        req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
        req.add_header("Cookie", self.cookie)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=120) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            self.cookie = None; self._login()
            req2 = urllib.request.Request(self.base+"/webapi/entry.cgi", data=body)
            req2.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
            req2.add_header("Cookie", self.cookie)
            with urllib.request.urlopen(req2, context=self.ctx, timeout=120) as r:
                return json.loads(r.read().decode())

    def mkdir(self, parent, name):
        r = self.call({"api":"SYNO.FileStation.CreateFolder","version":"2","method":"create",
                       "folder_path":parent, "name":'["%s"]' % name})
        return r

    def delete(self, path):
        r = self.call({"api":"SYNO.FileStation.Delete","version":"2","method":"delete",
                       "path":'["%s"]' % path})
        return r

    def move(self, src, dest_parent):
        r = self.call({"api":"SYNO.FileStation.Move","version":"2","method":"move",
                       "path":'["%s"]' % src, "dest_folder_path":dest_parent,
                       "overwrite":"true", "remove_src":"true"})
        return r

    def rename(self, path, new_name):
        """동일 위치에서 이름 변경 (FileStation.Rename)."""
        r = self.call({"api":"SYNO.FileStation.Rename","version":"2","method":"rename",
                       "path":'["%s"]' % path, "name":'["%s"]' % new_name})
        return r

    def get_info(self, path):
        r = self.call({"api":"SYNO.FileStation.List","version":"2","method":"getinfo",
                       "path":'["%s"]' % path,
                       "additional":'["real_path","size","type","perm"]'})
        if not r.get("success"):
            return {"ok": False, "error": r}
        f = r["data"]["files"][0]
        return {"ok": True, "size": f.get("additional", {}).get("size", 0),
                "name": f.get("name", "")}

    def write_stream(self, path, chunks, size=None, content_type="application/octet-stream"):
        """대용량 파일 스트리밍 업로드 (메모리 절약).

        chunks: bytes 이터러블(file.read 청크 등). 전체를 메모리에 올리지 않는다.
        """
        boundary = "----TSAKSTREAM9f13"
        parent = "/".join(path.split("/")[:-1]) or "/"
        fname = path.split("/")[-1]
        head = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"api\"\r\n\r\n"
            f"SYNO.FileStation.Upload\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"version\"\r\n\r\n2\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"method\"\r\n\r\nupload\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"path\"\r\n\r\n{parent}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"create_parents\"\r\n\r\ntrue\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{fname}\"\r\n"
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode()
        tail = f"\r\n--{boundary}--\r\n".encode()
        total = None
        if size is not None:
            total = len(head) + int(size) + len(tail)

        class _Body:
            def __init__(self):
                self._parts = [head]
                self._chunks = iter(chunks)
                self._done_head = False
                self._done_body = False
                self._finished = False
                self._buf = b""

            def read(self, n=-1):
                if n is None or n < 0:
                    n = 65536
                # 스트림 종료(EOF) 후에는 반드시 빈 바이트를 반환해야 한다.
                # (이전 구현은 EOF 를 알리지 못하고 boundary tail 을 무한 반복 반환해
                #  업로드 본문이 '------TSAKSTREAM…' 경계 문자열로 오염되었다.)
                if self._finished and not self._buf:
                    return b""
                while len(self._buf) < n and not self._finished:
                    if not self._done_head:
                        self._buf += self._parts.pop()
                        if not self._parts:
                            self._done_head = True
                        continue
                    if not self._done_body:
                        try:
                            self._buf += next(self._chunks)
                            continue
                        except StopIteration:
                            self._done_body = True
                            continue
                    # 본문 끝 → boundary tail 1회만 추가하고 스트림 종료
                    self._buf += tail
                    self._finished = True
                out, self._buf = self._buf[:n], self._buf[n:]
                return out

            def __len__(self):
                return total if total is not None else 0

        if not self.cookie:
            self._login()
        body = _Body()
        headers = {"Content-Type": f"multipart/form-data; boundary={boundary}",
                   "Cookie": self.cookie}
        if total is not None:
            headers["Content-Length"] = str(total)
        req = urllib.request.Request(self.base + "/webapi/entry.cgi", data=body, headers=headers)
        try:
            with urllib.request.urlopen(req, context=self.ctx, timeout=600) as r:
                return json.loads(r.read().decode())
        except Exception:
            self.cookie = None
            self._login()
            body = _Body()
            headers["Cookie"] = self.cookie
            req = urllib.request.Request(self.base + "/webapi/entry.cgi", data=body, headers=headers)
            with urllib.request.urlopen(req, context=self.ctx, timeout=600) as r:
                return json.loads(r.read().decode())

    def exists(self, path):
        parent = "/".join(path.split("/")[:-1]) or "/"
        name = path.split("/")[-1]
        r = self.list(parent)
        if not r.get("ok"): return False
        return any(f["name"] == name for f in r["files"])
