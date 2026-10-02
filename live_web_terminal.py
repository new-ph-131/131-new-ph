#!/usr/bin/env python3
import http.server
import socketserver
import threading
import subprocess
import os
import json
import time
import queue
import re

PORT = 8888
PIPE_PATH = "/tmp/pharoah_terminal.pipe"
ERROR_FILE = "latest_error.txt"

clients = []
clients_lock = threading.Lock()
log_history = []
history_lock = threading.Lock()

latest_error_text = ""
error_lock = threading.Lock()

if os.path.exists(PIPE_PATH):
    os.remove(PIPE_PATH)
os.mkfifo(PIPE_PATH)

def extract_and_save_error(raw_line):
    global latest_error_text
    lower = raw_line.lower()
    is_err = any(k in lower for k in [
        'error:', 'exception:', 'target ... failed', 'failed to compile',
        'unhandled exception', 'compilation failed', 'fatal:', 'error •',
        'build failed', 'undefined name', 'undefined_method', 'undefined_identifier'
    ])
    
    if is_err:
        with error_lock:
            # Accumulate error context (last 25 lines)
            current_lines = latest_error_text.split('\n') if latest_error_text else []
            current_lines.append(raw_line.strip())
            if len(current_lines) > 25:
                current_lines.pop(0)
            latest_error_text = '\n'.join(current_lines)
            
            try:
                with open(ERROR_FILE, "w", encoding="utf-8") as f:
                    f.write(latest_error_text)
            except Exception:
                pass
        
        # Broadcast error alert directly to UI
        broadcast_message("error_alert", raw_line.strip())

def broadcast_message(data_type, text):
    msg = json.dumps({"type": data_type, "data": text})
    with history_lock:
        log_history.append(msg)
        if len(log_history) > 3000:
            log_history.pop(0)
    with clients_lock:
        for q in list(clients):
            try:
                q.put_nowait(msg)
            except Exception:
                pass

def pipe_reader_thread():
    while True:
        with open(PIPE_PATH, 'r', encoding='utf-8', errors='ignore') as fifo:
            for line in fifo:
                extract_and_save_error(line)
                broadcast_message("log", line)

threading.Thread(target=pipe_reader_thread, daemon=True).start()

def execute_command_async(cmd):
    def run():
        global latest_error_text
        with error_lock:
            latest_error_text = ""
        broadcast_message("cmd", f"\n$ {cmd}\n")
        try:
            p = subprocess.Popen(
                cmd,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                cwd=os.getcwd()
            )
            for line in p.stdout:
                extract_and_save_error(line)
                broadcast_message("log", line)
            p.wait()
            status = "✔ SUCCESS (0)" if p.returncode == 0 else f"✖ FAILED ({p.returncode})"
            broadcast_message("status", f"\n[Process Finished: {status}]\n")
            if p.returncode != 0 and not latest_error_text:
                broadcast_message("error_alert", f"Process exited with non-zero exit code: {p.returncode}")
        except Exception as e:
            extract_and_save_error(str(e))
            broadcast_message("error", f"Execution error: {e}\n")
    threading.Thread(target=run, daemon=True).start()

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Codespaces Live Terminal • Smart Error Radar</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0B0F19;
      color: #E2E8F0;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro", "Segoe UI", sans-serif;
      height: 100vh;
      display: flex;
      flex-direction: column;
    }
    header {
      background: #1E293B;
      border-bottom: 1px solid #334155;
      padding: 10px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 10px;
    }
    .title {
      display: flex;
      align-items: center;
      gap: 10px;
      font-weight: 900;
      font-size: 14px;
      color: #38BDF8;
      letter-spacing: 0.5px;
    }
    .pulse {
      width: 10px; height: 10px; background: #10B981; border-radius: 50%;
      box-shadow: 0 0 10px #10B981;
      animation: blink 1.5s infinite;
    }
    @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }
    
    .actions { display: flex; gap: 8px; align-items: center; }
    button {
      background: #2563EB;
      color: #fff;
      border: none;
      padding: 8px 14px;
      border-radius: 8px;
      font-weight: 700;
      font-size: 11.5px;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: 0.2s;
    }
    button:active { transform: scale(0.97); }
    .btn-copy { background: #059669; font-size: 12px; }
    .btn-clear { background: #475569; }

    /* 🚨 LATEST ERROR RADAR CARD */
    #error-radar {
      display: none;
      background: #450A0A;
      border: 1.5px solid #EF4444;
      border-radius: 12px;
      margin: 10px 14px 4px 14px;
      padding: 12px 16px;
      box-shadow: 0 4px 20px rgba(239, 68, 68, 0.3);
      animation: pulseErr 2s infinite;
    }
    @keyframes pulseErr {
      0%, 100% { border-color: #EF4444; }
      50% { border-color: #F87171; box-shadow: 0 4px 25px rgba(248, 113, 113, 0.45); }
    }
    .err-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 8px;
    }
    .err-title {
      font-size: 12px;
      font-weight: 900;
      color: #FCA5A5;
      display: flex;
      align-items: center;
      gap: 6px;
      letter-spacing: 0.5px;
    }
    .err-content {
      background: #180505;
      padding: 10px 12px;
      border-radius: 8px;
      font-family: monospace;
      font-size: 11px;
      color: #FEE2E2;
      max-height: 120px;
      overflow-y: auto;
      white-space: pre-wrap;
      word-break: break-all;
      border: 1px solid rgba(239, 68, 68, 0.3);
    }
    .btn-copy-err {
      background: #DC2626;
      font-weight: 900;
      font-size: 11px;
      padding: 6px 12px;
    }
    .btn-dismiss {
      background: transparent;
      color: #FCA5A5;
      border: 1px solid #7F1D1D;
      font-size: 10px;
      padding: 4px 8px;
    }
    
    .quick-bar {
      background: #0F172A;
      border-bottom: 1px solid #1E293B;
      padding: 8px 14px;
      display: flex;
      gap: 8px;
      overflow-x: auto;
      white-space: nowrap;
    }
    .quick-btn {
      background: #1E293B;
      border: 1px solid #334155;
      color: #CBD5E1;
      padding: 6px 12px;
      font-size: 11px;
      border-radius: 6px;
    }
    .quick-btn.deploy {
      background: #065F46;
      border-color: #059669;
      color: #34D399;
      font-weight: 800;
    }
    .quick-btn:hover { background: #334155; color: #38BDF8; }

    #terminal {
      flex: 1;
      background: #020617;
      padding: 14px 16px;
      overflow-y: auto;
      font-family: "SF Mono", "Courier New", monospace;
      font-size: 12px;
      line-height: 1.5;
      word-break: break-all;
    }
    .line { white-space: pre-wrap; margin-bottom: 2px; }
    .cmd { color: #38BDF8; font-weight: bold; }
    .error { color: #F87171; font-weight: bold; background: rgba(239, 68, 68, 0.12); padding: 2px 4px; border-radius: 4px; }
    .warn { color: #FBBF24; }
    .success { color: #34D399; font-weight: bold; }

    footer {
      background: #1E293B;
      border-top: 1px solid #334155;
      padding: 8px 14px;
      display: flex;
      gap: 8px;
    }
    input[type="text"] {
      flex: 1;
      background: #0F172A;
      border: 1px solid #334155;
      color: #fff;
      padding: 9px 12px;
      border-radius: 8px;
      font-family: monospace;
      font-size: 12px;
      outline: none;
    }
    input[type="text"]:focus { border-color: #38BDF8; }
  </style>
</head>
<body>

  <header>
    <div class="title">
      <div class="pulse"></div>
      SMART TERMINAL RADAR
    </div>
    <div class="actions">
      <button class="btn-clear" onclick="clearTerminal()">🧹 Clear</button>
      <button class="btn-copy" onclick="copyAllLogs()">📋 All Logs</button>
    </div>
  </header>

  <!-- 🚨 LATEST ERROR RADAR PANEL -->
  <div id="error-radar">
    <div class="err-head">
      <div class="err-title">🚨 LATEST ERROR DETECTED</div>
      <div style="display: flex; gap: 6px;">
        <button class="btn-copy-err" onclick="copyLatestError()">📋 COPY ERROR FOR AI</button>
        <button class="btn-dismiss" onclick="dismissError()">✖</button>
      </div>
    </div>
    <div class="err-content" id="error-content">Listening for errors...</div>
  </div>

  <div class="quick-bar">
    <button class="quick-btn deploy" onclick="sendCmd('flutter build web -t lib/web_live_sync/web_main.dart --release --base-href \"/\" --pwa-strategy=none && npx wrangler pages deploy build/web --project-name=pharoah-erp')">🚀 1-Click Build & Deploy</button>
    <button class="quick-btn" onclick="sendCmd('flutter analyze lib/web_live_sync/')">🔍 Analyze Web</button>
    <button class="quick-btn" onclick="sendCmd('git status')">🌿 Git Status</button>
  </div>

  <div id="terminal"></div>

  <footer>
    <input type="text" id="cmdInput" placeholder="Command daalein (e.g. flutter analyze)..." onkeydown="if(event.key==='Enter') runInputCmd()">
    <button onclick="runInputCmd()">▶ Run</button>
  </footer>

  <script>
    const term = document.getElementById('terminal');
    const errRadar = document.getElementById('error-radar');
    const errContent = document.getElementById('error-content');
    let allLogs = [];
    let errorLines = [];

    function appendLine(text, type) {
      allLogs.push(text);
      if (allLogs.length > 3000) allLogs.shift();

      const div = document.createElement('div');
      div.className = 'line';
      
      let lower = text.toLowerCase();
      if (type === 'cmd') div.classList.add('cmd');
      else if (type === 'status' || lower.includes('success')) div.classList.add('success');
      else if (lower.includes('error:') || lower.includes('exception:') || lower.includes('failed') || lower.includes('error •')) {
        div.classList.add('error');
        showErrorInRadar(text);
      }
      else if (lower.includes('warning:')) div.classList.add('warn');

      div.textContent = text;
      term.appendChild(div);
      term.scrollTop = term.scrollHeight;
    }

    function showErrorInRadar(text) {
      errorLines.push(text.trim());
      if (errorLines.length > 15) errorLines.shift();
      errContent.textContent = errorLines.join('\\n');
      errRadar.style.display = 'block';
    }

    function dismissError() {
      errRadar.style.display = 'none';
      errorLines = [];
    }

    function copyTextFallback(text, onSuccess) {
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(onSuccess).catch(() => {
          fallbackPrompt(text);
        });
      } else {
        fallbackPrompt(text);
      }
    }

    function fallbackPrompt(text) {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      try {
        document.execCommand('copy');
        alert("✔ Copied to Clipboard!");
      } catch (err) {
        alert("Clipboard access blocked. Please manually copy from screen.");
      }
      document.body.removeChild(ta);
    }

    function copyLatestError() {
      const errText = errContent.textContent;
      if (!errText || errText.includes('Listening for errors...')) {
        alert("Abhi koi error nahi hai!");
        return;
      }
      const formatted = "🚨 Build/Terminal me ye Latest Error aa raha hai:\\n\\n```\\n" + errText + "\\n```\\n\\nIsko fix karke terminal code do.";
      copyTextFallback(formatted, () => {
        const btn = document.querySelector('.btn-copy-err');
        btn.textContent = "✔ COPIED FOR AI!";
        setTimeout(() => { btn.textContent = "📋 COPY ERROR FOR AI"; }, 2500);
      });
    }

    function copyAllLogs() {
      const fullText = allLogs.join('');
      if (!fullText) {
        alert("Terminal log khali hai!");
        return;
      }
      copyTextFallback(fullText, () => {
        const btn = document.querySelector('.btn-copy');
        btn.textContent = "✔ COPIED!";
        setTimeout(() => { btn.textContent = "📋 All Logs"; }, 2000);
      });
    }

    function clearTerminal() {
      term.innerHTML = '';
      allLogs = [];
      dismissError();
    }

    function sendCmd(cmd) {
      dismissError();
      fetch('/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ command: cmd })
      });
    }

    function runInputCmd() {
      const input = document.getElementById('cmdInput');
      const val = input.value.trim();
      if (val) {
        sendCmd(val);
        input.value = '';
      }
    }

    function connectSSE() {
      const evtSource = new EventSource('/events');
      evtSource.onmessage = function(e) {
        try {
          const payload = JSON.parse(e.data);
          if (payload.type === 'error_alert') {
            showErrorInRadar(payload.data);
          } else {
            appendLine(payload.data, payload.type);
          }
        } catch(_) {}
      };
      evtSource.onerror = function() {
        evtSource.close();
        setTimeout(connectSSE, 2000);
      };
    }
    connectSSE();
  </script>
</body>
</html>
"""

class CustomHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode('utf-8'))
        elif self.path == '/latest-error':
            with error_lock:
                err = latest_error_text if latest_error_text else "No recent errors."
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(err.encode('utf-8'))
        elif self.path == '/events':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self.end_headers()

            q = queue.Queue()
            with history_lock:
                for item in log_history:
                    q.put_nowait(item)

            with clients_lock:
                clients.append(q)

            try:
                while True:
                    try:
                        msg = q.get(timeout=15)
                        self.wfile.write(f"data: {msg}\n\n".encode('utf-8'))
                        self.wfile.flush()
                    except queue.Empty:
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
            except Exception:
                with clients_lock:
                    if q in clients:
                        clients.remove(q)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/run':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body)
            cmd = data.get('command', '')
            if cmd:
                execute_command_async(cmd)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"running"}')

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

server = ThreadedHTTPServer(('0.0.0.0', PORT), CustomHandler)
print(f"🚀 Smart Error Radar Terminal running on http://localhost:{PORT}")
execute_command_async("echo '🚨 Smart Live Terminal with Error Radar Connected Successfully!'")
try:
    server.serve_forever()
except Exception:
    pass
