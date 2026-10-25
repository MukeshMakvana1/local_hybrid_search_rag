class OllamaModel {
  final String name;
  final String model;
  final int size;
  final String digest;
  final String family;
  final String parameterSize;
  final String quantizationLevel;
  final List<String> capabilities;
  final DateTime? modifiedAt;

  OllamaModel({
    required this.name,
    required this.model,
    required this.size,
    required this.digest,
    required this.family,
    required this.parameterSize,
    required this.quantizationLevel,
    required this.capabilities,
    this.modifiedAt,
  });

  factory OllamaModel.fromJson(Map<String, dynamic> json) {
    final details = json['details'] as Map<String, dynamic>? ?? {};
    final caps = (json['capabilities'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    DateTime? modAt;
    if (json['modified_at'] != null) {
      try {
        modAt = DateTime.parse(json['modified_at'].toString());
      } catch (_) {}
    }

    return OllamaModel(
      name: json['name']?.toString() ?? '',
      model: json['model']?.toString() ?? json['name']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      digest: json['digest']?.toString() ?? '',
      family: details['family']?.toString() ?? '',
      parameterSize: details['parameter_size']?.toString() ?? '',
      quantizationLevel: details['quantization_level']?.toString() ?? '',
      capabilities: caps,
      modifiedAt: modAt,
    );
  }

  String get formattedSize {
    if (size <= 0) return '';
    final gb = size / (1024 * 1024 * 1024);
    if (gb >= 1.0) {
      return '${gb.toStringAsFixed(1)} GB';
    }
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  bool get isEmbeddingModel {
    final n = name.toLowerCase();
    return n.contains('embed') || n.contains('bge') || n.contains('minilm') || n.contains('nomic');
  }

  String get speedBadge {
    if (isEmbeddingModel) return '🎯 Embedder';
    final n = name.toLowerCase();
    final p = parameterSize.toLowerCase();
    if (n.contains('0.5b') || n.contains('0.6b') || n.contains('1b') || p.contains('751') || p.contains('0.5') || p.contains('0.6')) {
      return '⚡ Instant';
    } else if (n.contains('1.5b') || n.contains('2b') || n.contains('3b') || p.contains('1.') || p.contains('3.')) {
      return '🚀 Fast';
    } else if (n.contains('r1') || n.contains('deepseek') || n.contains('reason')) {
      return '🧠 Reasoning';
    } else if (n.contains('coder') || n.contains('code')) {
      return '💻 Coder';
    } else {
      return '⭐ Quality';
    }
  }

  String get displayName {
    final badge = speedBadge;
    if (parameterSize.isNotEmpty) {
      return '$badge  $name ($parameterSize • $formattedSize)';
    } else if (formattedSize.isNotEmpty) {
      return '$badge  $name ($formattedSize)';
    }
    return '$badge  $name';
  }
}
