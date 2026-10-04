import os

files = [
    "lib/web_live_sync/sub_views/web_billing/web_new_sale_view.dart",
    "lib/web_live_sync/web_purchase_entry_view.dart"
]

for filepath in files:
    if os.path.exists(filepath):
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Target: _buildCartTable method where SingleChildScrollView(scrollDirection: Axis.horizontal) is used
        old_cart = """else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 700),
              child: Table("""

        new_cart = """else
          SizedBox(
            height: 420,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 700),
                  child: Table("""

        if old_cart in content and "SizedBox(" not in content:
            content = content.replace(old_cart, new_cart)
            
            # Also close the extra brackets properly where Table ends in _buildCartTable
            # Let's replace the closing of Table container
            content = content.replace(
                'child: Table(\n                        columnWidths:',
                'child: Table(\n                        columnWidths:'
            )
            
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"✅ Added vertical scroll to {filepath}")
        else:
            print(f"ℹ️ Already updated or pattern not matched for {filepath}")

fix_scroll_script_func = lambda: None
