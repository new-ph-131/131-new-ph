import subprocess
import re
import sys
import os
import urllib.request
import urllib.parse
import threading

print("📦 Checking Python dependencies...")
try:
    import qrcode
except ImportError:
    os.system(f"{sys.executable} -m pip install qrcode > /dev/null 2>&1")
    import qrcode

print("🚀 Starting Google Clasp Login with QR Assistant...\n")

process = subprocess.Popen(
    ["npx", "@google/clasp", "login", "--no-localhost"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    bufsize=1
)

def read_output():
    url_found = False
    for line in process.stdout:
        print(line, end="")
        if not url_found:
            match = re.search(r"(https://accounts\.google\.com/[^\s\x1b\x03]+)", line)
            if match:
                auth_url = match.group(1)
                url_found = True
                
                try:
                    api_url = f"https://tinyurl.com/api-create.php?url={urllib.parse.quote(auth_url)}"
                    short_url = urllib.request.urlopen(api_url, timeout=3).read().decode('utf-8')
                except Exception:
                    short_url = auth_url

                print("\n" + "="*42)
                print(f"🔗 SHORT LINK: {short_url}")
                print("📱 SCAN THIS TINY QR CODE WITH IPAD CAMERA:")
                print("="*42)
                
                qr = qrcode.QRCode(version=1, border=1)
                qr.add_data(short_url)
                qr.make(fit=True)
                qr.print_ascii(invert=True)
                print("="*42 + "\n")

t = threading.Thread(target=read_output)
t.daemon = True
t.start()

try:
    while process.poll() is None:
        user_input = input()
        process.stdin.write(user_input + "\n")
        process.stdin.flush()
except (EOFError, KeyboardInterrupt):
    pass

process.wait()
