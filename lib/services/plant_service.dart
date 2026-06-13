import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class PlantService {
  // Claude API endpoint
  static const String _apiUrl = 'https://api.anthropic.com/v1/messages';

  // .env থেকে API key নেওয়া
  static String get _apiKey => dotenv.env['CLAUDE_API_KEY'] ?? '';

  /// ছবি নিয়ে Claude API তে পাঠাবে, result return করবে
  static Future<PlantResult> identifyPlant(File imageFile) async {
    // Step 1: Image কে Base64 এ convert করো
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    // Step 2: Image এর type বের করো
    final mimeType = _getMimeType(imageFile.path);

    // Step 3: API request body তৈরি করো
    final body = jsonEncode({
      "model": "claude-opus-4-6",
      "max_tokens": 1024,
      "messages": [
        {
          "role": "user",
          "content": [
            {
              // Image part
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": mimeType,
                "data": base64Image,
              },
            },
            {
              // Text instruction part
              "type": "text",
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
          ],
        }
      ],
    });

    // Step 4: HTTP POST request পাঠাও
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: body,
      );

      // Step 5: Response check করো
      if (response.statusCode == 200) {
        return _parseResponse(response.body);
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('ইন্টারনেট সংযোগ নেই');
    } catch (e) {
      rethrow;
    }
  }

  /// Claude এর response থেকে PlantResult বানাও
  static PlantResult _parseResponse(String responseBody) {
    final decoded = jsonDecode(responseBody);

    // Claude এর actual text content বের করো
    final content = decoded['content'][0]['text'] as String;

    // JSON parse করো
    final plantData = jsonDecode(content);

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

  /// File extension থেকে MIME type বের করো
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

/// Plant identification এর result model
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

  /// Plant না পাওয়া গেলে এই constructor ব্যবহার হবে
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
