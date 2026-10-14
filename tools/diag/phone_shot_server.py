#!/usr/bin/env python3
"""Phone -> machine photo drop: open the URL on the phone, pick the photo,
press send. The file lands in ./shots/ where the agent picks it up.

Run:  python3 phone_shot_server.py [port]
Page: http://<machine-lan-ip>:<port>/
"""
import html
import http.server
import os
import pathlib
import sys
import time
import urllib.parse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
SHOTS = pathlib.Path(__file__).resolve().parent / "shots"
SHOTS.mkdir(exist_ok=True)

PAGE = """<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ANE shot drop</title>
<style>
body{font-family:sans-serif;margin:24px;max-width:520px}
h1{font-size:18px}
#st{margin-top:12px;font-size:15px;min-height:1.4em}
input,button{font-size:18px;padding:10px;margin-top:12px;width:100%;box-sizing:border-box}
</style></head><body>
<h1>写真を送る (ANE shot drop)</h1>
<input id="f" type="file" accept="image/*">
<button onclick="send()">送信</button>
<div id="st"></div>
<script>
async function send(){
  const st=document.getElementById('st');
  const f=document.getElementById('f').files[0];
  if(!f){st.textContent='ファイルを選んでください';return;}
  st.textContent='送信中… '+(f.size/1024).toFixed(0)+'KB';
  try{
    const r=await fetch('/upload?name='+encodeURIComponent(f.name),{method:'POST',body:f});
    st.textContent=r.ok?('送信完了: '+f.name):('失敗: '+r.status);
  }catch(e){st.textContent='失敗: '+e;}
}
</script></body></html>
"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = PAGE.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if not self.path.startswith("/upload"):
            self.send_error(404)
            return
        q = urllib.parse.urlparse(self.path)
        name = urllib.parse.parse_qs(q.query).get("name", ["shot.jpg"])[0]
        name = os.path.basename(name) or "shot.jpg"
        if not name.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".heic")):
            name += ".jpg"
        length = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(length)
        # serial numbered copy: keep every upload
        stamp = time.strftime("%H%M%S")
        dest = SHOTS / f"{stamp}_{name}"
        dest.write_bytes(data)
        print(f"[drop] {dest} ({len(data)} bytes)", flush=True)
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, fmt, *args):
        print(f"[http] {self.address_string()} {fmt % args}", flush=True)

if __name__ == "__main__":
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"listening on 0.0.0.0:{PORT}, saving to {SHOTS}", flush=True)
    srv.serve_forever()
