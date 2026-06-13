import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

class PlantService {
  static const String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  static Future<PlantResult> identifyPlant(File imageFile) async {
    // Image compress করো — size ছোট হলে 429 error কম আসবে
    final compressedBytes = await FlutterImageCompress.compressWithFile(
      imageFile.path,
      quality: 60,
      minWidth: 800,
      minHeight: 800,
    );

    if (compressedBytes == null) {
      throw Exception('ছবি compress করা যায়নি');
    }

    final base64Image = base64Encode(compressedBytes);
    final mimeType = _getMimeType(imageFile.path);

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {
              "inline_data": {
                "mime_type": mimeType,
                "data": base64Image,
              }
            },
            {
              "text": """You are a plant identification expert.
Analyze this image and identify the plant.

Respond ONLY in this exact JSON format, nothing else:
{
  "plant_name": "Common name of the plant",
  "scientific_name": "Scientific/Latin name",
  "family": "Plant family name",
  "description": "2-3 sentences about this plant",
  "care_tips": "1-2 basic care tips",
  "is_plant": true
}

If the image does NOT contain a plant, respond with:
{
  "is_plant": false,
  "message": "No plant detected in the image"
}"""
            }
          ]
        }
      ]
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        return _parseResponse(response.body);
      } else if (response.statusCode == 429) {
        throw Exception('অনেক বেশি request হয়েছে, একটু পরে try করুন');
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('ইন্টারনেট সংযোগ নেই');
    } catch (e) {
      rethrow;
    }
  }

  static PlantResult _parseResponse(String responseBody) {
    final decoded = jsonDecode(responseBody);

    final content =
        decoded['candidates'][0]['content']['parts'][0]['text'] as String;

    // Gemini কখনো markdown backticks দেয়, সেটা remove করো
    final cleanJson =
        content.replaceAll('```json', '').replaceAll('```', '').trim();

    final plantData = jsonDecode(cleanJson);

    if (plantData['is_plant'] == false) {
      return PlantResult.notAPlant(
        plantData['message'] ?? 'ছবিতে কোনো গাছ পাওয়া যায়নি',
      );
    }

    return PlantResult(
      plantName: plantData['plant_name'] ?? 'Unknown',
      scientificName: plantData['scientific_name'] ?? 'Unknown',
      family: plantData['family'] ?? 'Unknown',
      description: plantData['description'] ?? '',
      careTips: plantData['care_tips'] ?? '',
      isPlant: true,
    );
  }

  static String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

class PlantResult {
  final String plantName;
  final String scientificName;
  final String family;
  final String description;
  final String careTips;
  final bool isPlant;
  final String? errorMessage;

  PlantResult({
    required this.plantName,
    required this.scientificName,
    required this.family,
    required this.description,
    required this.careTips,
    required this.isPlant,
    this.errorMessage,
  });

  factory PlantResult.notAPlant(String message) {
    return PlantResult(
      plantName: '',
      scientificName: '',
      family: '',
      description: '',
      careTips: '',
      isPlant: false,
      errorMessage: message,
    );
  }
}
