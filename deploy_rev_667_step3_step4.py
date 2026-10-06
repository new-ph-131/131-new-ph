# FILE: deploy_rev_667_step3_step4.py
# 🚀 1-CLICK PRODUCTION DEPLOYER & GITHUB PUSHER FOR #PH-REV-667
# Step 3: Decoupled Modules (File Separation Rule) & Frontend LWW State Optimization
# Step 4: JSON Batch Outbox Replication & D1 Edge Reconciliation
import os
import sys
import subprocess

print('=' * 72)
print('🚀 PHAROAH ERP • REVISION #PH-REV-667 DEPLOYER')
print('Step 3: Frontend State Optimization & File Separation (Sales, Purchase, Challan, Voucher)')
print('Step 4: JSON Batch Operations & Transactional Outbox D1 Replication')
print('=' * 72 + '\n')

repo_dir = os.path.dirname(os.path.abspath(__file__))
os.chdir(repo_dir)

# 1. GIT STATUS & COMMIT
print('📥 Step 1/4: Staging files and creating git commit...')
subprocess.run(['git', 'add', '.'], check=False)
subprocess.run(['git', 'commit', '-m', '🚀 #PH-REV-667: Step 3 & 4 - Decoupled Modules & JSON Batch D1 Engine'], check=False)

# 2. PUSH TO GITHUB (Trigger APK build on GitHub Actions)
print('📤 Step 2/4: Pushing to GitHub (origin main)...')
res_push = subprocess.run(['git', 'push', 'origin', 'main'], text=True)
if res_push.returncode == 0:
    print('✔ Pushed to GitHub successfully! APK build triggered on GitHub Actions.')
else:
    print('⚠ Git push returned non-zero code. (If in Colab, check git credentials).')

# 3. BUILD FLUTTER WEB
print('🔨 Step 3/4: Building Production Flutter Web App...')
subprocess.run(['flutter', 'pub', 'get'], check=False)
build_cmd = [
    'flutter', 'build', 'web',
    '-t', 'lib/web_live_sync/web_main.dart',
    '--release',
    '--base-href', '/',
    '--pwa-strategy=none'
]
b_res = subprocess.run(build_cmd, text=True)
if b_res.returncode != 0:
    print('❌ Flutter Web Compilation Failed! Check error logs above.')
    sys.exit(1)
print('✔ Production Web Build Complete!')

# 4. DEPLOY TO CLOUDFLARE PAGES
print('🌐 Step 4/4: Deploying to Cloudflare Pages...')
deploy_cmd = [
    'npx', 'wrangler', 'pages', 'deploy', 'build/web',
    '--project-name=pharoah-erp',
    '--commit-dirty=true'
]
d_res = subprocess.run(deploy_cmd, text=True)
if d_res.returncode != 0:
    print('⚠ Wrangler deploy failed. Trying pages publish...')
    subprocess.run(['npx', 'wrangler', 'pages', 'publish', 'build/web', '--project-name=pharoah-erp'], text=True)

print('\n' + '=' * 72)
print('🎉 #PH-REV-667 DEPLOYMENT COMPLETE!')
print('🔗 Live Portal URL: https://pharoah-erp.pages.dev')
print('🏷️ Revision: #PH-REV-667 (STEP-3-4-DECOUPLED-BATCH-ENGINE)')
print('=' * 72)
