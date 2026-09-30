import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'pharoah_manager.dart';

class AuditLogsView extends StatelessWidget {
  const AuditLogsView({super.key});

  @override
  Widget build(BuildContext context) {
    // Access PharoahManager for log data
    final ph = Provider.of<PharoahManager>(context);
    
    // Reverse logs to show the most recent actions at the top
    final logs = ph.logs.reversed.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("System Audit Logs"),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 15),
                  const Text(
                    "No system logs recorded yet.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                
                // Set color and icon based on action type
                Color actionColor = Colors.blue;
                IconData actionIcon = Icons.info_outline;

                if (log.action.contains("DELETE")) {
                  actionColor = Colors.red;
                  actionIcon = Icons.delete_forever;
                } else if (log.action.contains("CANCEL")) {
                  actionColor = Colors.orange;
                  actionIcon = Icons.block;
                } else if (log.action.contains("SALE")) {
                  actionColor = Colors.green;
                  actionIcon = Icons.shopping_cart_checkout;
                } else if (log.action.contains("PURCHASE")) {
                  actionColor = Colors.indigo;
                  actionIcon = Icons.downloading;
                } else if (log.action.contains("RESET")) {
                  actionColor = Colors.deepPurple;
                  actionIcon = Icons.restart_alt;
                }

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: actionColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(actionIcon, color: actionColor, size: 24),
                    ),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          log.action,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: actionColor,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          DateFormat('dd/MM/yy HH:mm').format(log.time),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        log.details,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
