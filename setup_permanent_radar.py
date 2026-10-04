import os
import subprocess
import time
import socketserver
import http.server
import threading
import json

PORT = 8888
LOG_FILE = ".terminal_live.log"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Pharoah ERP • Live Radar Monitor</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background-color: #0b132b; color: #e2e8f0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace; padding: 16px; }
    .header { display: flex; align-items: center; justify-content: space-between; background: #1e293b; padding: 14px 18px; border-radius: 14px; border: 1px solid #334155; margin-bottom: 14px; flex-wrap: wrap; gap: 10px; }
    .title { font-size: 15px; font-weight: 900; color: #38bdf8; display: flex; align-items: center; gap: 8px; }
    .actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    .btn { padding: 10px 16px; border-radius: 10px; font-size: 12px; font-weight: 800; cursor: pointer; border: none; transition: 0.15s; display: inline-flex; align-items: center; gap: 6px; }
    .btn-err { background: #dc2626; color: #ffffff; }
    .btn-copy { background: #2563eb; color: #ffffff; }
    .btn-check { background: #10b981; color: #ffffff; }
    .badge { padding: 6px 12px; border-radius: 8px; font-size: 11px; font-weight: 800; }
    .badge-ok { background: #064e3b; color: #34d399; border: 1px solid #059669; }
    .badge-warn { background: #78350f; color: #fbbf24; border: 1px solid #d97706; }
    .badge-err { background: #450a0a; color: #f87171; border: 1px solid #dc2626; }
    .toast { display: none; background: #10b981; color: white; padding: 10px 16px; border-radius: 8px; font-size: 12px; font-weight: bold; margin-bottom: 12px; text-align: center; }
    .console-box { background: #070d19; border: 1.5px solid #1e293b; border-radius: 14px; padding: 16px; min-height: 520px; max-height: 72vh; overflow-y: auto; font-size: 12.5px; line-height: 1.6; white-space: pre-wrap; word-break: break-all; -webkit-user-select: text; user-select: text; }
    .line-ok { color: #34d399; font-weight: bold; }
    .line-warn { color: #fbbf24; }
    .line-err { color: #f87171; font-weight: bold; }
    .line-info { color: #38bdf8; }
  </style>
  <script>
    let rawContent = "";
    let lastContent = "";

    function showToast(msg) {
      const t = document.getElementById('toast');
      t.innerText = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 2500);
    }

    function copyToClipboard(text, successMsg) {
      if (!text) {
        showToast("⚠️ Koi text nahi mila copy karne ke liye!");
        return;
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(() => {
          showToast(successMsg);
        }).catch(() => fallbackCopy(text, successMsg));
      } else {
        fallbackCopy(text, successMsg);
      }
    }

    function fallbackCopy(text, successMsg) {
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
      showToast(successMsg);
    }

    function copyAll() {
      copyToClipboard(rawContent, "📋 Pura output copy ho gaya! Chat me paste kar de.");
    }

    function copyErrorsOnly() {
      const lines = rawContent.split('\\n');
      const errLines = lines.filter(l => {
        const lower = l.toLowerCase();
        return lower.includes('error') || lower.includes('warning') || lower.includes('failure') || lower.includes('issue') || lower.includes('line ') || lower.includes('exception');
      });
      if (errLines.length === 0) {
        showToast("ℹ️ Koi error line nahi mili (All Clean)!");
      } else {
        copyToClipboard(errLines.join('\\n'), "⚠️ Sirf ERROR/WARNING lines copy ho gayi! Chat me paste karein.");
      }
    }

    async function triggerRecheck() {
      showToast("⏳ Fresh Flutter Analyze run ho raha hai...");
      try {
        await fetch('/api/run-check', { method: 'POST' });
      } catch (e) {}
    }

    async function poll() {
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
            .replace(/(SUCCESS|No issues found|All clear|0 issues found!)/gi, '<span class="line-ok">$1</span>')
            .replace(/(warning|caution|issues found)/gi, '<span class="line-warn">$1</span>')
            .replace(/(error|failed|exception|fatal|undefined_named_parameter|context)/gi, '<span class="line-err">$1</span>')
            .replace(/(STEP \\d+|Analyzing|Verifying)/gi, '<span class="line-info">$1</span>');

          screen.innerHTML = colored || "Waiting for terminal output...";
          screen.scrollTop = screen.scrollHeight;

          const lower = data.content.toLowerCase();
          if (lower.includes("error") || lower.includes("failed") || lower.includes("exception")) {
            badge.className = "badge badge-err";
            badge.innerText = "❌ ERRORS FOUND";
          } else if (lower.includes("warning") || lower.includes("issue")) {
            badge.className = "badge badge-warn";
            badge.innerText = "⚠️ WARNINGS";
          } else {
            badge.className = "badge badge-ok";
            badge.innerText = "✅ ALL CLEAN (0 ERRORS)";
          }
        }
      } catch(e) {}
    }

    setInterval(poll, 1200);
    poll();
  </script>
</head>
<body>
  <div class="header">
    <div class="title">
      <span>⚡</span>
      <span>PHAROAH ERP • LIVE RADAR</span>
    </div>
    <div class="actions">
      <button onclick="copyErrorsOnly()" class="btn btn-err">⚠️ COPY ERRORS ONLY</button>
      <button onclick="copyAll()" class="btn btn-copy">📋 COPY FULL LOG</button>
      <button onclick="triggerRecheck()" class="btn btn-check">🔍 RE-RUN ANALYZE</button>
      <div id="statusBadge" class="badge badge-ok">MONITORING</div>
    </div>
  </div>

  <div id="toast" class="toast"></div>
  <div id="terminalScreen" class="console-box">Connecting to Live Radar...</div>
</body>
</html>
"""

def run_flutter_analysis():
    timestamp = time.strftime("%H:%M:%S")
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write(f"[{timestamp}] 🔍 Running full project analysis across lib/ ...\n\n")

    res = subprocess.run(["flutter", "analyze"], capture_output=True, text=True)
    output = (res.stdout or "") + (res.stderr or "")

    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(output)
        f.write(f"\n[{time.strftime('%H:%M:%S')}] 🏁 Analysis Finished. Code: {res.returncode}\n")

class RadarHandler(http.server.SimpleHTTPRequestHandler):
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
            self.wfile.write(json.dumps({'content': log_content}).encode('utf-8'))
        else:
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML_TEMPLATE.encode('utf-8'))

    def do_POST(self):
        if self.path == '/api/run-check':
            threading.Thread(target=run_flutter_analysis).start()
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'started'}).encode('utf-8'))

    def log_message(self, format, *args):
        pass

# 1. Kill any zombie servers on port 8888
subprocess.run("fuser -k 8888/tcp > /dev/null 2>&1 || true", shell=True)

# 2. Run initial check now
print("🔍 Step 1: Running deep Flutter analysis to capture latest errors...")
run_flutter_analysis()

# 3. Start Server in Thread
print("🌐 Step 2: Starting Live Terminal Radar on Port 8888...")
socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("0.0.0.0", PORT), RadarHandler)
server_thread = threading.Thread(target=httpd.serve_forever)
server_thread.daemon = True
server_thread.start()

print("\n" + "="*65)
print("🎉 LIVE RADAR IS NOW ACTIVE PERMANENTLY ON PORT 8888!")
print("📱 iPad User: Codespace ke PORTS tab me jakar 8888 open karein")
print("="*65 + "\n")

# 4. Display current error log right now in terminal so user can copy immediately
print("📄 LATEST OUTPUT CAPTURED:")
print("-" * 50)
with open(LOG_FILE, "r", encoding="utf-8") as f:
    print(f.read())
print("-" * 50)
print("👉 Upar jo bhi Error / Warning aayi hai, use copy karke yahan bhej dein!")

# Keep main script alive
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    pass
