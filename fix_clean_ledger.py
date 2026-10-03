import re

path = 'lib/web_live_sync/pharoah_web_manager.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix any python f-string artifacts in Dart code
content = re.sub(
    r"'particulars'\s*:\s*f\s*\"([^\"]*)\"\s*,",
    r"'particulars': \"\1\",",
    content
)

content = re.sub(
    r"'particulars'\s*:\s*f\s*'([^']*)'\s*,",
    r"'particulars': '\1',",
    content
)

# Clean line-by-line replacement for particulars line
lines = content.splitlines()
new_lines = []
for line in lines:
    if 'particulars' in line and 'v.type.toUpperCase()' in line:
        line = "        'particulars': \"${v.type.toUpperCase()} (${v.paymentMode})\",\"".replace('","', '",')
    new_lines.append(line)

content = '\n'.join(new_lines)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('✔ Successfully sanitized pharoah_web_manager.dart via fix_clean_ledger.py')
