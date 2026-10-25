import 'document_chunk.dart';

enum MessageRole { user, assistant, system }

class ChatMessage {
  final MessageRole role;
  String content;
  final DateTime timestamp;
  bool isStreaming;
  bool isFallback;
  List<SearchResult> sources;
  int? retrievalDurationMs;
  int? generationDurationMs;
  int tokenCount;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.isFallback = false,
    this.sources = const [],
    this.retrievalDurationMs,
    this.generationDurationMs,
    this.tokenCount = 0,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  double? get tokensPerSecond {
    if (generationDurationMs != null && generationDurationMs! > 0 && tokenCount > 0) {
      return (tokenCount / (generationDurationMs! / 1000.0));
    }
    return null;
  }
}
