import http.server
import socketserver
import os
import json
import time
import subprocess
import threading

PORT = 8888
LOG_FILE = ".terminal_live.log"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Codespaces Live Radar Terminal</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background-color: #0b132b; color: #e2e8f0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace; padding: 18px; }
    .header { display: flex; align-items: center; justify-content: space-between; background: #1e293b; padding: 14px 20px; border-radius: 14px; border: 1px solid #334155; margin-bottom: 16px; flex-wrap: wrap; gap: 10px; }
    .title { font-size: 16px; font-weight: 900; color: #38bdf8; display: flex; align-items: center; gap: 10px; }
    .actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
    .btn { padding: 9px 15px; border-radius: 9px; font-size: 12px; font-weight: 900; cursor: pointer; border: none; transition: 0.15s; display: inline-flex; align-items: center; gap: 6px; }
    .btn-run { background: #10b981; color: #ffffff; }
    .btn-run:active { background: #059669; transform: scale(0.96); }
    .btn-copy { background: #2563eb; color: #ffffff; }
    .btn-copy:active { background: #1d4ed8; transform: scale(0.96); }
    .btn-clear { background: #334155; color: #94a3b8; }
    .btn-clear:active { background: #1e293b; transform: scale(0.96); }
    .badge { padding: 6px 12px; border-radius: 8px; font-size: 11px; font-weight: bold; }
    .badge-ok { background: #064e3b; color: #34d399; border: 1px solid #059669; }
    .badge-warn { background: #78350f; color: #fbbf24; border: 1px solid #d97706; }
    .badge-err { background: #450a0a; color: #f87171; border: 1px solid #dc2626; }
    .console-box { background: #070d19; border: 1.5px solid #1e293b; border-radius: 14px; padding: 18px; min-height: 480px; max-height: 75vh; overflow-y: auto; font-size: 13px; line-height: 1.6; white-space: pre-wrap; word-break: break-all; }
    .line-ok { color: #34d399; font-weight: bold; }
    .line-warn { color: #fbbf24; }
    .line-err { color: #f87171; font-weight: bold; }
    .line-info { color: #38bdf8; }
    .footer { margin-top: 12px; font-size: 11px; color: #64748b; text-align: center; }
  </style>
</head>
<body>
  <div class="header">
    <div class="title">
      <span>🚀</span>
      <span>PHAROAH ERP • LIVE TERMINAL RADAR</span>
    </div>
    <div class="actions">
      <button id="runCheckBtn" onclick="triggerRunCheck()" class="btn btn-run">🔍 RUN LATEST CHECK</button>
      <button id="copyBtn" onclick="copyOutput()" class="btn btn-copy">📋 COPY LOG</button>
      <button onclick="clearScreen()" class="btn btn-clear">🧹 CLEAR</button>
      <div id="statusBadge" class="badge badge-ok">ALL CLEAN • 0 ERRORS</div>
    </div>
  </div>

  <div id="terminalScreen" class="console-box">Initializing Terminal Stream...</div>

  <div class="footer">
    Tap 'RUN LATEST CHECK' to re-verify errors • Tap 'COPY LOG' to copy fresh output
  </div>

  <script>
    let rawContent = "";
    let lastContent = "";

    async function pollLogs() {
      try {
        const res = await fetch('/api/log');
        const data = await res.json();
        if (data.content !== lastContent) {
          lastContent = data.content;
          rawContent = data.content;
          const screen = document.getElementById('terminalScreen');
          const badge = document.getElementById('statusBadge');
          
          let colored = data.content
            .replace(/(&)/g, "&amp;").replace(/(<)/g, "&lt;").replace(/(>)/g, "&gt;")
            .replace(/(SUCCESS|No issues found|All clear|verified|All tests passed!)/gi, '<span class="line-ok">$1</span>')
            .replace(/(warning|caution|issues found)/gi, '<span class="line-warn">$1</span>')
            .replace(/(error|failed|exception|fatal|undefined_named_parameter)/gi, '<span class="line-err">$1</span>')
            .replace(/(STEP \\d+|Analyzing|Verifying|EXECUTING FLUTTER TEST)/gi, '<span class="line-info">$1</span>');
          
          screen.innerHTML = colored || "Waiting for terminal activity...";
          screen.scrollTop = screen.scrollHeight;

          const lower = data.content.toLowerCase();
          if (lower.includes("error") || lower.includes("fatal") || lower.includes("failed")) {
            badge.className = "badge badge-err";
            badge.innerText = "ERROR DETECTED";
          } else if (lower.includes("warning") || lower.includes("issues found")) {
            badge.className = "badge badge-warn";
            badge.innerText = "WARNINGS FOUND";
          } else {
            badge.className = "badge badge-ok";
            badge.innerText = "ALL CLEAN • 0 ERRORS";
          }
        }
      } catch (e) {}
    }

    async function triggerRunCheck() {
      const btn = document.getElementById('runCheckBtn');
      const orig = btn.innerHTML;
      btn.innerHTML = "⏳ RUNNING...";
      btn.style.opacity = "0.7";
      try {
        await fetch('/api/run-check', { method: 'POST' });
        setTimeout(() => {
          btn.innerHTML = orig;
          btn.style.opacity = "1";
        }, 1500);
      } catch (e) {
        btn.innerHTML = orig;
        btn.style.opacity = "1";
      }
    }

    function copyOutput() {
      const textToCopy = rawContent || document.getElementById('terminalScreen').innerText;
      if (!textToCopy) return;
      navigator.clipboard.writeText(textToCopy).then(() => {
        const btn = document.getElementById('copyBtn');
        const originalText = btn.innerHTML;
        btn.innerHTML = "✅ COPIED!";
        btn.style.background = "#10b981";
        setTimeout(() => {
          btn.innerHTML = originalText;
          btn.style.background = "#2563eb";
        }, 2000);
      }).catch(err => {
        alert("Clipboard error: " + err);
      });
    }

    async function clearScreen() {
      document.getElementById('terminalScreen').innerHTML = "Screen cleared. Waiting for next check...";
      rawContent = "";
      try {
        await fetch('/api/clear', { method: 'POST' });
      } catch (e) {}
    }

    setInterval(pollLogs, 1000);
    pollLogs();
  </script>
</body>
</html>
"""

def execute_check_in_background():
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write("==========================================\n")
        f.write("🔍 LATEST CHECK: Running Analyzer & Tests...\n")
        f.write("==========================================\n")
    
    # Run analyzer
    res1 = subprocess.run(["dart", "analyze", "lib/sync_bridge"], capture_output=True, text=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(res1.stdout + "\n" + res1.stderr + "\n")
    
    # Run flutter test
    res2 = subprocess.run(["flutter", "test", "test/sync_bridge_test.dart"], capture_output=True, text=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(res2.stdout + "\n" + res2.stderr + "\n")
        f.write("==========================================\n")
        f.write(f"🎉 LATEST CHECK COMPLETED at {time.strftime('%H:%M:%S')}\n")
        f.write("==========================================\n")

class LiveTerminalHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/log':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            log_content = ""
            if os.path.exists(LOG_FILE):
                try:
                    with open(LOG_FILE, 'r', encoding='utf-8', errors='ignore') as f:
                        log_content = f.read()
                except Exception as e:
                    log_content = str(e)
            self.wfile.write(json.dumps({'content': log_content, 'time': time.time()}).encode('utf-8'))
        else:
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML_TEMPLATE.encode('utf-8'))

    def do_POST(self):
        if self.path == '/api/run-check':
            threading.Thread(target=execute_check_in_background).start()
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'started'}).encode('utf-8'))
        elif self.path == '/api/clear':
            with open(LOG_FILE, "w", encoding="utf-8") as f:
                f.write("Screen cleared. Ready for next command.\n")
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'cleared'}).encode('utf-8'))

    def log_message(self, format, *args):
        pass

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", PORT), LiveTerminalHandler) as httpd:
    httpd.serve_forever()
