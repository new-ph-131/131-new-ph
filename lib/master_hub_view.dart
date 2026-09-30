// FILE: lib/master_hub_view.dart (UPDATED)

import 'package:flutter/material.dart';
import 'widgets.dart';
import 'party_master.dart';
import 'product_master.dart';
import 'route_master_view.dart';
import 'company_master_view.dart';
import 'salt_master_view.dart';
import 'drug_type_master_view.dart';
import 'batch_master_view.dart';
// --- NAYA IMPORT ZAROORI HAI ---
import 'administration/ca_profile_view.dart'; 

class MasterHubView extends StatelessWidget {
  const MasterHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      appBar: AppBar(
        title: const Text("Master Data Hub"),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("PRIMARY BUSINESS MASTERS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey, letterSpacing: 1.2)),
            const SizedBox(height: 15),

            // --- SECTION 1: CORE MASTERS ---
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.2,
              children: [
                ActionIconBtn(
                  title: "Parties / Ledgers", 
                  icon: Icons.people_alt_rounded, 
                  color: Colors.indigo, 
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const PartyMasterView()))
                ),
                ActionIconBtn(
                  title: "Item Master", 
                  icon: Icons.inventory_2_rounded, 
                  color: Colors.purple, 
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ProductMasterView()))
                ),
                // NAYA BATCH MASTER ENTRY
                ActionIconBtn(
                  title: "Batch Master", 
                  icon: Icons.layers_outlined, 
                  color: Colors.indigo.shade900, 
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const BatchMasterView()))
                ),
                
                // --- CA PROFILE BUTTON (यह अब सही काम करेगा) ---
                ActionIconBtn(
                  title: "CA Profile / Audit", 
                  icon: Icons.assignment_ind_rounded, 
                  color: Colors.orange.shade900, 
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const CaProfileView()))
                ),
                
                ActionIconBtn(
                  title: "Route Master", 
                  icon: Icons.map_rounded, 
                  color: Colors.teal, 
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const RouteMasterView()))
                ),
              ],
            ),

            const SizedBox(height: 30),

            const Text("PHARMA & LOGISTICS MASTERS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey, letterSpacing: 1.2)),
            const SizedBox(height: 15),

            // --- SECTION 2: PHARMA MASTERS ---
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.2,
              children: [
                ActionIconBtn(title: "Company Master", icon: Icons.business_rounded, color: Colors.brown, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const CompanyMasterView()))),
                ActionIconBtn(title: "Salt Master", icon: Icons.science_rounded, color: Colors.deepOrange, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SaltMasterView()))),
                ActionIconBtn(title: "Drug Categories", icon: Icons.verified_user_rounded, color: Colors.cyan.shade700, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DrugTypeMasterView()))),
              ],
            ),
            
            const SizedBox(height: 30),
            
            // --- INFO CARD ---
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)),
              child: const Row(children: [
                Icon(Icons.tips_and_updates_outlined, color: Colors.orange, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text("Use CA Profile to activate Audit Mode and redirect all emails to your accountant.", style: TextStyle(fontSize: 11, color: Colors.blueGrey))),
              ]),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
