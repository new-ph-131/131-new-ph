import sys
import os

def patch_section(filepath, start_comment, end_comment):
    if not os.path.exists(filepath):
        print(f"❌ File not found: {filepath}")
        return
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    start_idx = content.find(start_comment)
    end_idx = content.find(end_comment)
    
    if start_idx == -1 or end_idx == -1:
        print(f"❌ Markers not found in {filepath}: '{start_comment}' or '{end_comment}'")
        return
    
    new_code = sys.stdin.read()
    prefix = content[:start_idx + len(start_comment)]
    suffix = content[end_idx:]
    
    updated = prefix + "\n" + new_code + "\n" + suffix
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(updated)
    print(f"✔ Successfully patched {filepath} between markers!")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python patch_file.py <file> <start_marker> <end_marker>")
    else:
        patch_section(sys.argv[1], sys.argv[2], sys.argv[3])
