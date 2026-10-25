import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/ollama_model.dart';

class OllamaService {
  String baseUrl;
  final http.Client _client = http.Client();

  OllamaService({this.baseUrl = 'http://127.0.0.1:11434'});

  /// Check whether Ollama service is reachable
  Future<bool> checkHealth() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get list of installed Ollama models
  Future<List<OllamaModel>> getInstalledModels() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final List rawModels = data['models'] as List? ?? [];
        return rawModels.map((m) => OllamaModel.fromJson(m)).toList();
      } else {
        throw Exception('Failed to load models: HTTP ${res.statusCode}');
      }
    } catch (e) {
      throw Exception('Could not connect to Ollama at $baseUrl. Ensure Ollama is running.');
    }
  }

  /// Fast batch embedding calculation with instant graceful fallback
  Future<List<List<double>>> getBatchEmbeddings(
    List<String> texts, {
    String? model,
    String keepAlive = '30m',
  }) async {
    if (texts.isEmpty) return [];

    if (model != null && model.isNotEmpty) {
      try {
        final res = await _client.post(
          Uri.parse('$baseUrl/api/embed'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'input': texts,
            'keep_alive': keepAlive,
          }),
        ).timeout(const Duration(seconds: 45));

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data['embeddings'] is List) {
            final List rawList = data['embeddings'] as List;
            return rawList.map((e) {
              final vec = (e as List).map((n) => (n as num).toDouble()).toList();
              return normalizeVector(vec);
            }).toList();
          }
        }
      } catch (_) {}
    }

    // Immediate resilient fallback: compute normalized hash embeddings without repeating network timeouts
    return texts.map((t) => computeHashEmbedding(t, dimensions: 384)).toList();
  }

  /// Generate dense vector embedding for single text
  Future<List<double>> getEmbedding(
    String text, {
    String? model,
    String keepAlive = '30m',
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return List.filled(384, 0.0);
    }

    if (model != null && model.isNotEmpty) {
      try {
        final embedRes = await _client.post(
          Uri.parse('$baseUrl/api/embed'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'input': cleanText,
            'keep_alive': keepAlive,
          }),
        ).timeout(const Duration(seconds: 15));

        if (embedRes.statusCode == 200) {
          final data = jsonDecode(utf8.decode(embedRes.bodyBytes));
          if (data['embeddings'] is List && (data['embeddings'] as List).isNotEmpty) {
            final first = (data['embeddings'] as List).first as List;
            final vec = first.map((e) => (e as num).toDouble()).toList();
            return normalizeVector(vec);
          }
        }
      } catch (_) {}

      try {
        final legacyRes = await _client.post(
          Uri.parse('$baseUrl/api/embeddings'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'prompt': cleanText,
            'keep_alive': keepAlive,
          }),
        ).timeout(const Duration(seconds: 15));

        if (legacyRes.statusCode == 200) {
          final data = jsonDecode(utf8.decode(legacyRes.bodyBytes));
          if (data['embedding'] is List) {
            final emb = data['embedding'] as List;
            final vec = emb.map((e) => (e as num).toDouble()).toList();
            return normalizeVector(vec);
          }
        }
      } catch (_) {}
    }

    return computeHashEmbedding(cleanText, dimensions: 384);
  }

  /// Normalize vector (L2 norm) for fast dot-product similarity
  static List<double> normalizeVector(List<double> vector) {
    double sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = sqrt(sumSq);
    if (norm > 0.0000001) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }
    return vector;
  }

  /// Resilient fallback embedding generator
  static List<double> computeHashEmbedding(String text, {int dimensions = 384}) {
    final vector = List.filled(dimensions, 0.0);
    final tokens = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').split(RegExp(r'\s+'));

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.isEmpty) continue;

      int h1 = 5381;
      for (int c = 0; c < token.length; c++) {
        h1 = ((h1 << 5) + h1) + token.codeUnitAt(c);
      }
      final idx1 = (h1.abs()) % dimensions;
      final sign1 = (h1 & 1 == 0) ? 1.0 : -1.0;
      vector[idx1] += sign1 * 1.5;

      if (i + 1 < tokens.length) {
        final bigram = '$token ${tokens[i + 1]}';
        int h2 = 7919;
        for (int c = 0; c < bigram.length; c++) {
          h2 = ((h2 << 5) + h2) + bigram.codeUnitAt(c);
        }
        final idx2 = (h2.abs()) % dimensions;
        final sign2 = (h2 & 1 == 0) ? 1.0 : -1.0;
        vector[idx2] += sign2 * 2.0;
      }
    }

    return normalizeVector(vector);
  }

  /// Stream chat completion from Ollama supporting both standard content and reasoning thinking tokens
  Stream<String> chatStream({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
    String keepAlive = '30m',
  }) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
    request.headers['Content-Type'] = 'application/json';

    final Map<String, dynamic> body = {
      'model': model,
      'messages': messages,
      'stream': true,
      'keep_alive': keepAlive,
      'options': {
        'temperature': temperature,
        'num_predict': ?maxTokens,
      },
    };

    request.body = jsonEncode(body);

    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode != 200) {
      final errBody = await streamedResponse.stream.bytesToString();
      throw Exception('Ollama error (${streamedResponse.statusCode}): $errBody');
    }

    await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (chunk.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(chunk) as Map<String, dynamic>;
        final message = parsed['message'] as Map<String, dynamic>?;
        if (message != null) {
          final content = message['content']?.toString() ?? '';
          final thinking = message['thinking']?.toString() ?? '';

          if (content.isNotEmpty) {
            yield content;
          } else if (thinking.isNotEmpty) {
            yield thinking;
          }
        }
      } catch (_) {}
    }
  }

  void dispose() {
    _client.close();
  }
}
