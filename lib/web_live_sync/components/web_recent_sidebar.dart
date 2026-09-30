// FILE: lib/web_live_sync/components/web_recent_sidebar.dart

import 'package:flutter/material.dart';

class WebRecentSidebar extends StatelessWidget {
  final String currentView;
  final List<Map<String, dynamic>> recentShortcuts;
  final VoidCallback onHomeTap;
  final Function(String title, IconData icon, String navKey) onActionTap;
  final ValueChanged<int> onRemoveShortcut;
  final VoidCallback onClearAll;

  const WebRecentSidebar({
    super.key,
    required this.currentView,
    required this.recentShortcuts,
    required this.onHomeTap,
    required this.onActionTap,
    required this.onRemoveShortcut,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(right: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 15),
          InkWell(
            onTap: onHomeTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: currentView == "HOME" ? const Color(0xFF2563EB) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: currentView == "HOME" ? Border.all(color: const Color(0xFF60A5FA), width: 1) : null,
              ),
              child: const Row(
                children: [
                  Icon(Icons.dashboard_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Text(
                    "Main Dashboard",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            child: Divider(color: Colors.white10, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "RECENT SHORTCUTS",
                  style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                if (recentShortcuts.isNotEmpty)
                  InkWell(
                    onTap: onClearAll,
                    child: const Text(
                      "Clear",
                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: recentShortcuts.isEmpty
                ? const Center(
                    child: Text(
                      "No recent shortcuts yet.\nOpen any action to add.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                  )
                : ListView.builder(
                    itemCount: recentShortcuts.length,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemBuilder: (context, index) {
                      final item = recentShortcuts[index];
                      final String title = item['title'] as String? ?? '';
                      final IconData icon = item['icon'] as IconData? ?? Icons.star_rounded;
                      final String moduleKey = item['module'] as String? ?? '';
                      final bool isSelected = currentView == moduleKey;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected ? Border.all(color: const Color(0xFF38BDF8)) : Border.all(color: Colors.white10),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          leading: Icon(icon, color: const Color(0xFF38BDF8), size: 16),
                          title: Text(
                            title,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: InkWell(
                            onTap: () => onRemoveShortcut(index),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.close_rounded, size: 14, color: Colors.white38),
                            ),
                          ),
                          onTap: () => onActionTap(title, icon, moduleKey),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black38,
            child: const Center(
              child: Text(
                "Pharoah ERP Web v1.0.9",
                style: TextStyle(color: Colors.white24, fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
