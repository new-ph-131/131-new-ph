// FILE: lib/gateway/export_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart'; // Zip ke liye
import '../pharoah_manager.dart';
import 'company_registry_model.dart';

class ExportService {
  final PharoahManager ph;
  ExportService(this.ph);

  // ===========================================================================
  // 📤 EXPORT: Pura Data + Images ka Bundle banana
  // ===========================================================================
  Future<void> exportEntireCompany(CompanyProfile comp) async {
    try {
      final archive = Archive();
      final root = await getApplicationDocumentsDirectory();
      
      // 1. Scan Company Directory (Data + Images)
      final companyPath = '${root.path}/Pharoah_Data/${comp.id}';
      final companyDir = Directory(companyPath);
      if (!await companyDir.exists()) return;

      // Sabhi files ko zip archive mein add karna
      List<FileSystemEntity> files = companyDir.listSync(recursive: true);
      for (var file in files) {
        if (file is File) {
          String relPath = file.path.replaceFirst(companyPath, "");
          List<int> bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
        }
      }

      // 2. Add Registry Profile (Iske bina restore nahi hota)
      String profileJson = jsonEncode(comp.toMap());
      archive.addFile(ArchiveFile("profile.json", profileJson.length, utf8.encode(profileJson)));

      // 3. Zip file ko save aur share karna
      final zipData = ZipEncoder().encode(archive);
      final tempDir = await getTemporaryDirectory();
      final zipFile = File('${tempDir.path}/${comp.name.replaceAll(' ', '_')}_Backup.pharoah');
      await zipFile.writeAsBytes(zipData!);

      await Share.shareXFiles([XFile(zipFile.path)], subject: 'Backup: ${comp.name}');
    } catch (e) {
      print("Export Error: $e");
    }
  }

  // ===========================================================================
  // 📥 IMPORT: Bundle se Restore karna
  // ===========================================================================
  Future<bool> importCompany() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['pharoah'] // Sirf hamari backup file
      );
      
      if (result == null) return false;
      File pickedFile = File(result.files.single.path!);
      Uint8List bytes = await pickedFile.readAsBytes();
      
      // Zip ko decode karna
      final archive = ZipDecoder().decodeBytes(bytes);
      CompanyProfile? importedProfile;

      final root = await getApplicationDocumentsDirectory();

      // Pehle profile dhundo
      for (final file in archive) {
        if (file.name == "profile.json") {
          importedProfile = CompanyProfile.fromMap(jsonDecode(utf8.decode(file.content)));
          break;
        }
      }

      if (importedProfile == null) return false;

      // Folder create karo aur saari files extract karo
      final targetPath = '${root.path}/Pharoah_Data/${importedProfile.id}';
      for (final file in archive) {
        if (file.name != "profile.json") {
          final outFile = File('$targetPath/${file.name}');
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content);
        }
      }

      // Registry mein jodh do taaki dukan dikhne lage
      if (!ph.companiesRegistry.any((c) => c.id == importedProfile!.id)) {
        ph.companiesRegistry.add(importedProfile);
        await ph.saveRegistry();
      }

      return true;
    } catch (e) {
      print("Import Error: $e");
      return false;
    }
  }
}
