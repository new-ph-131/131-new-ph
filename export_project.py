import os
import zipfile

output_filename = "pharoah_erp_complete_project.zip"
exclude_dirs = {'.git', 'build', '.dart_tool', '.pub-cache', '.wrangler', 'ios/Pods', 'android/.gradle', '.idea', '.vscode'}

print(f"📦 Packing entire project into {output_filename}...")

count = 0
with zipfile.ZipFile(output_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk('.'):
        # Exclude unwanted directories
        dirs[:] = [d for d in dirs if not any(os.path.relpath(os.path.join(root, d), '.').startswith(ex) for ex in exclude_dirs)]
        
        for file in files:
            filepath = os.path.join(root, file)
            if os.path.abspath(filepath) == os.path.abspath(output_filename):
                continue
            arcname = os.path.relpath(filepath, '.')
            zipf.write(filepath, arcname)
            count += 1

print(f"✅ Success! Total {count} files packed into: {os.path.abspath(output_filename)}")
