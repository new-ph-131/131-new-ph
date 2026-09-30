import http.server
import socketserver
import json
import os
import re

PORT = 8085
LOG_FILE = "/tmp/codespace_live.log"
STATUS_FILE = "/tmp/codespace_status.json"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Pharoah ERP • Live Monitor</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background-color: #0F172A; color: #F8FAFC; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace; padding: 15px; }
    .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #334155; padding-bottom: 12px; margin-bottom: 15px; }
    .title { font-size: 16px; font-weight: 800; color: #38BDF8; }
    .badge { padding: 4px 10px; border-radius: 6px; font-size: 11px; font-weight: 800; }
    .badge.success { background: #064E3B; color: #34D399; border: 1px solid #059669; }
    .badge.error { background: #7F1D1D; color: #F87171; border: 1px solid #DC2626; }
    .badge.running { background: #78350F; color: #FBBF24; border: 1px solid #D97706; }
    
    .toolbar { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 15px; }
    button { background: #2563EB; color: white; border: none; padding: 10px 14px; border-radius: 8px; font-weight: 700; font-size: 12px; cursor: pointer; display: flex; align-items: center; gap: 6px; }
    button.error-btn { background: #DC2626; }
    button.sec-btn { background: #334155; }
    button:active { transform: scale(0.97); }

    .toast { display: none; background: #10B981; color: white; padding: 8px 14px; border-radius: 6px; font-size: 12px; font-weight: bold; margin-bottom: 12px; }

    .terminal-box { background: #030712; border: 1px solid #1E293B; border-radius: 12px; padding: 15px; }
    textarea#raw-box { width: 100%; height: 60vh; background: transparent; color: #E2E8F0; border: none; font-family: monospace; font-size: 12.5px; line-height: 1.5; resize: none; outline: none; -webkit-user-select: text; user-select: text; }
  </style>
  <script>
    function showToast(msg) {
      const t = document.getElementById('toast');
      t.innerText = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 2500);
    }

    function copyText(text, msg) {
      const el = document.createElement('textarea');
      el.value = text;
      el.setAttribute('readonly', '');
      el.style.position = 'absolute';
      el.style.left = '-9999px';
      document.body.appendChild(el);
      el.select();
      el.setSelectionRange(0, 99999);
      document.execCommand('copy');
      document.body.removeChild(el);
      showToast(msg);
    }

    function copyAll() {
      const val = document.getElementById('raw-box').value;
      copyText(val, '✅ Pura terminal log copy ho gaya!');
    }

    function copyOnlyErrors() {
      const val = document.getElementById('raw-box').value;
      const lines = val.split('\\n');
      const errLines = lines.filter(l => l.toLowerCase().includes('error') || l.toLowerCase().includes('warning') || l.toLowerCase().includes('failure') || l.toLowerCase().includes('line '));
      if(errLines.length === 0) {
        showToast('ℹ️ Koi error line nahi mili!');
      } else {
        copyText(errLines.join('\\n'), '⚠️ Sirf Error Lines copy ho gayi!');
      }
    }

    function selectAll() {
      const box = document.getElementById('raw-box');
      box.focus();
      box.setSelectionRange(0, box.value.length);
      showToast('👉 Text select ho gaya, iPad ke popup se Copy karein!');
    }

    async function refresh() {
      try {
        const res = await fetch('/api/data');
        const data = await res.json();
        document.getElementById('status-badge').className = 'badge ' + data.status_class;
        document.getElementById('status-badge').innerText = data.status_text;
        document.getElementById('raw-box').value = data.output;
      } catch(e) {}
    }
    setInterval(refresh, 2000);
  </script>
</head>
<body>
  <div class="header">
    <div class="title">⚡ PHAROAH TERMINAL MONITOR</div>
    <div id="status-badge" class="badge running">LIVE</div>
  </div>

  <div id="toast" class="toast"></div>

  <div class="toolbar">
    <button class="error-btn" onclick="copyOnlyErrors()">⚠️ COPY ERRORS ONLY</button>
    <button onclick="copyAll()">📋 COPY ALL OUTPUT</button>
    <button class="sec-btn" onclick="selectAll()">📱 SELECT ALL</button>
    <button class="sec-btn" onclick="window.open('/raw', '_blank')">📄 OPEN PLAIN TEXT</button>
  </div>

  <div class="terminal-box">
    <textarea id="raw-box" readonly spellcheck="false">Loading output...</textarea>
  </div>
</body>
</html>
"""

class Handler(http.server.SimpleHTTPRequestHandler):
  def do_GET(self):
    if self.path == "/raw":
      output = "No log found."
      if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
          output = f.read()
      self.send_response(200)
      self.send_header("Content-Type", "text/plain; charset=utf-8")
      self.end_headers()
      self.wfile.write(output.encode("utf-8"))
      return

    if self.path == "/api/data":
      output = "No output yet."
      if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "r", encoding="utf-8", errors="ignore") as f:
          output = f.read()

      status = {"status_class": "running", "status_text": "MONITORING", "last_cmd": "live", "last_updated": "Live"}
      if os.path.exists(STATUS_FILE):
        try:
          with open(STATUS_FILE, "r") as f:
            status = json.load(f)
        except:
          pass

      status["output"] = output
      self.send_response(200)
      self.send_header("Content-Type", "application/json")
      self.end_headers()
      self.wfile.write(json.dumps(status).encode("utf-8"))
      return

    self.send_response(200)
    self.send_header("Content-Type", "text/html")
    self.end_headers()
    self.wfile.write(HTML_TEMPLATE.encode("utf-8"))

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
  httpd.serve_forever()
