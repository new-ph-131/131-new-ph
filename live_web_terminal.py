#!/usr/bin/env python3
import http.server
import socketserver
import threading
import subprocess
import os
import json
import time
import queue

PORT = 8888
PIPE_PATH = "/tmp/pharoah_terminal.pipe"

clients = []
clients_lock = threading.Lock()
log_history = []
history_lock = threading.Lock()

if os.path.exists(PIPE_PATH):
    os.remove(PIPE_PATH)
os.mkfifo(PIPE_PATH)

def broadcast_message(data_type, text):
    msg = json.dumps({"type": data_type, "data": text})
    with history_lock:
        log_history.append(msg)
        if len(log_history) > 2000:
            log_history.pop(0)
    with clients_lock:
        for q in list(clients):
            try:
                q.put_nowait(msg)
            except:
                pass

def pipe_reader_thread():
    while True:
        with open(PIPE_PATH, 'r') as fifo:
            for line in fifo:
                broadcast_message("log", line)

threading.Thread(target=pipe_reader_thread, daemon=True).start()

def execute_command_async(cmd):
    def run():
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
                broadcast_message("log", line)
            p.wait()
            status = "✔ SUCCESS (0)" if p.returncode == 0 else f"✖ FAILED ({p.returncode})"
            broadcast_message("status", f"\n[Process Finished: {status}]\n")
        except Exception as e:
            broadcast_message("error", f"Execution error: {e}\n")
    threading.Thread(target=run, daemon=True).start()

HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Codespaces Live Terminal Port</title>
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
      padding: 12px 18px;
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
      font-weight: 800;
      font-size: 15px;
      color: #38BDF8;
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
      font-size: 12px;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: 0.2s;
    }
    button:active { transform: scale(0.97); }
    .btn-copy { background: #059669; font-size: 13px; padding: 9px 16px; box-shadow: 0 0 12px rgba(16, 185, 129, 0.4); }
    .btn-clear { background: #475569; }
    
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
    .quick-btn:hover { background: #334155; color: #38BDF8; }

    #terminal {
      flex: 1;
      background: #020617;
      padding: 16px;
      overflow-y: auto;
      font-family: "SF Mono", "Courier New", monospace;
      font-size: 12.5px;
      line-height: 1.5;
      word-break: break-all;
    }
    .line { white-space: pre-wrap; margin-bottom: 2px; }
    .cmd { color: #38BDF8; font-weight: bold; }
    .error { color: #F87171; font-weight: bold; background: rgba(239, 68, 68, 0.1); padding: 2px 4px; border-radius: 4px; }
    .warn { color: #FBBF24; }
    .success { color: #34D399; font-weight: bold; }

    footer {
      background: #1E293B;
      border-top: 1px solid #334155;
      padding: 10px 16px;
      display: flex;
      gap: 10px;
    }
    input[type="text"] {
      flex: 1;
      background: #0F172A;
      border: 1px solid #334155;
      color: #fff;
      padding: 10px 14px;
      border-radius: 8px;
      font-family: monospace;
      font-size: 13px;
      outline: none;
    }
    input[type="text"]:focus { border-color: #38BDF8; }
  </style>
</head>
<body>

  <header>
    <div class="title">
      <div class="pulse"></div>
      CODESPACE LIVE TERMINAL PORT (ACTIVE)
    </div>
    <div class="actions">
      <button class="btn-clear" onclick="clearTerminal()">🧹 Clear</button>
      <button class="btn-copy" onclick="copyAllLogs()">📋 COPY FOR AI</button>
    </div>
  </header>

  <div class="quick-bar">
    <button class="quick-btn" onclick="sendCmd('flutter analyze lib/web_live_sync/')">🔍 Analyze Web</button>
    <button class="quick-btn" onclick="sendCmd('git status')">🌿 Git Status</button>
  </div>

  <div id="terminal"></div>

  <footer>
    <input type="text" id="cmdInput" placeholder="Command daalein..." onkeydown="if(event.key==='Enter') runInputCmd()">
    <button onclick="runInputCmd()">▶ Run</button>
  </footer>

  <script>
    const term = document.getElementById('terminal');
    let allLogs = [];

    function appendLine(text, type) {
      allLogs.push(text);
      if (allLogs.length > 2500) allLogs.shift();

      const div = document.createElement('div');
      div.className = 'line';
      
      let lower = text.toLowerCase();
      if (type === 'cmd') div.classList.add('cmd');
      else if (type === 'status' || lower.includes('success')) div.classList.add('success');
      else if (lower.includes('error:') || lower.includes('exception:') || lower.includes('failed')) div.classList.add('error');
      else if (lower.includes('warning:')) div.classList.add('warn');

      div.textContent = text;
      term.appendChild(div);
      term.scrollTop = term.scrollHeight;
    }

    function clearTerminal() {
      term.innerHTML = '';
      allLogs = [];
    }

    function copyAllLogs() {
      const fullText = allLogs.join('');
      if (!fullText) {
        alert("Terminal me abhi koi log nahi hai!");
        return;
      }
      navigator.clipboard.writeText(fullText).then(() => {
        const btn = document.querySelector('.btn-copy');
        btn.textContent = "✔ COPIED!";
        btn.style.background = "#15803D";
        setTimeout(() => {
          btn.textContent = "📋 COPY FOR AI";
          btn.style.background = "#059669";
        }, 2000);
      });
    }

    function sendCmd(cmd) {
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

    // Auto-reconnect EventSource with ping handler
    function connectSSE() {
      const evtSource = new EventSource('/events');
      evtSource.onmessage = function(e) {
        try {
          const payload = JSON.parse(e.data);
          appendLine(payload.data, payload.type);
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
                        # Keep alive heartbeat ping for Safari on iPad
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
            except:
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
execute_command_async("echo '⚡ Live Web Terminal connected successfully!'")
try:
    server.serve_forever()
except:
    pass
