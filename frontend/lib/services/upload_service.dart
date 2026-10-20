import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

class UploadService {
  static Future<String?> uploadImage(XFile image) async {
    try {
      final activeBase = await ApiService.getActiveBaseUrl();
      final headers = await ApiService.authHeaders();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$activeBase/upload'),
      );

      request.headers.addAll({
        'Authorization': headers['Authorization'] ?? '',
      });

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            bytes,
            filename: image.name.isNotEmpty ? image.name : 'upload.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            image.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return data['imageUrl'];
      }

      debugPrint('Upload failed (${response.statusCode}): ${response.body}');
      throw Exception('Upload failed with status ${response.statusCode}');
    } catch (e) {
      debugPrint('UploadService error: $e');
      return null;
    }
  }
}
