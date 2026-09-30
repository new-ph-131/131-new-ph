import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

class PharoahAiEngine {
  
  static Future<Map<String, dynamic>> processBills(List<File> images, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    String apiKey = prefs.getString('geminiKey') ?? "";
    bool autoOffline = prefs.getBool('autoOffline') ?? true;

    String geminiErrorLog = "";

    // --- 1. CLOUD AI (GEMINI) ATTEMPT ---
    if (apiKey.trim().isNotEmpty) {
      try {
        debugPrint("Attempting Cloud AI Extraction...");
        return await _runGeminiVision(images, apiKey, mode);
      } catch (e) {
        debugPrint("Cloud AI Failed: $e");
        geminiErrorLog = e.toString(); 
        
        // Agar user ne offline fallback mana kiya hai toh error throw karein
        if (!autoOffline) {
          throw Exception("Cloud AI Error: $geminiErrorLog");
        }
      }
    } 
    
    // --- 2. OFFLINE AI FALLBACK (ML KIT) ---
    debugPrint("Falling back to Offline AI...");
    return await _runOfflineMLKit(images, geminiErrorLog);
  }

  // =========================================================================
  // ONLINE ENGINE: GOOGLE GEMINI 1.5 FLASH (STABLE ENDPOINT)
  // =========================================================================
  static Future<Map<String, dynamic>> _runGeminiVision(List<File> images, String apiKey, String mode) async {
    // UPDATED: v1 endpoint aur gemini-1.5-flash model name
    final String url = "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=$apiKey";
    
    // Sirf pehli image ko process kar rahe hain (Single Page)
    List<int> imageBytes = await images.first.readAsBytes();
    String base64Image = base64Encode(imageBytes);

    // Prompt updated for better Indian Invoices understanding
    String prompt = """
      You are a professional Data Entry Operator. Scan this Indian Invoice image and extract data into a STRICTURE JSON format.
      Mode: This is a $mode invoice.
      
      Instructions:
      1. 'partyName': Extract the Supplier/Vendor name.
      2. 'billNo': Find the Invoice Number or Bill No.
      3. 'items': List all products found in the table.
      4. For each item, extract: 'name', 'qty' (number), 'rate' (unit price), 'total' (qty * rate).
      5. Return ONLY the JSON object. No extra text, no markdown.
      
      Format Example:
      {
        "partyName": "ABC PHARMA",
        "billNo": "INV-101",
        "items": [
          {"name": "DOLO 650", "qty": 10, "rate": 30.50, "total": 305.0}
        ]
      }
    """;

    Map<String, dynamic> payload = {
      "contents": [
        {
          "parts": [
            {"text": prompt},
            {
              "inline_data": {
                "mime_type": "image/jpeg",
                "data": base64Image
              }
            }
          ]
        }
      ],
      "generationConfig": {
        "response_mime_type": "application/json" // Force JSON output
      }
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      
      // Extracting the text part from Gemini's nested response
      String rawResponseText = data['candidates'][0]['content']['parts'][0]['text'];
      
      // Clean up the response if markdown is returned
      int startIndex = rawResponseText.indexOf('{');
      int endIndex = rawResponseText.lastIndexOf('}');
      
      if (startIndex != -1 && endIndex != -1) {
        String cleanJson = rawResponseText.substring(startIndex, endIndex + 1);
        Map<String, dynamic> result = jsonDecode(cleanJson);
        
        result["status"] = "ONLINE";
        result["message"] = "Cloud AI successfully extracted structured data.";
        return result;
      } else {
        throw Exception("AI response was not in a valid JSON format.");
      }
    } else {
      var errorBody = jsonDecode(response.body);
      String errorMessage = errorBody['error'] != null ? errorBody['error']['message'] : "Unknown API Error";
      throw Exception(errorMessage);
    }
  }

  // =========================================================================
  // OFFLINE ENGINE: GOOGLE ML KIT (TEXT ONLY)
  // =========================================================================
  static Future<Map<String, dynamic>> _runOfflineMLKit(List<File> images, String previousError) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    String fullText = "";

    try {
      for (var img in images) {
        final inputImage = InputImage.fromFile(img);
        final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
        fullText += "${recognizedText.text}\n\n";
      }
    } catch (e) {
      textRecognizer.close();
      throw Exception("Offline OCR Engine failed: $e");
    }
    
    textRecognizer.close();

    String userMessage = "Processed Offline via OCR.";
    if (previousError.isNotEmpty) {
      userMessage = "Cloud AI Unavailable. Switched to Basic Offline OCR.";
    }

    return {
      "status": "OFFLINE",
      "partyName": "Manual Entry Required",
      "billNo": "N/A",
      "items": [],
      "raw_text": fullText.isEmpty ? "No text could be read from image." : fullText,
      "message": userMessage
    };
  }
}
