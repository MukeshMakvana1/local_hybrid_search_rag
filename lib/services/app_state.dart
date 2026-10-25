import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/document_chunk.dart';
import '../models/ollama_model.dart';
import 'document_processor.dart';
import 'hybrid_search_service.dart';
import 'knowledge_graph_service.dart';
import 'ollama_service.dart';

const String kRagSystemPrompt = '''
You are a friendly, highly intelligent and knowledgeable assistant that provides complete, accurate, and insightful answers.
Answer the user's question using only the context provided below.
When responding, you MUST NOT reference the existence of the context, directly or indirectly.
Instead, you MUST treat the context as if its contents are entirely part of your working memory.
''';

const String kFallbackSystemPrompt = '''
You are a helpful AI assistant. When you don't know something, be honest about it. Provide clear, concise, and accurate responses.
''';

class AppState extends ChangeNotifier {
  final OllamaService ollamaService;
  late final DocumentProcessor documentProcessor;
  late final HybridSearchService searchService;
  late final KnowledgeGraphService knowledgeGraphService;

  AppState({OllamaService? service})
      : ollamaService = service ?? OllamaService() {
    documentProcessor = DocumentProcessor(ollamaService: ollamaService);
    searchService = HybridSearchService(ollamaService: ollamaService);
    knowledgeGraphService = KnowledgeGraphService(ollamaService: ollamaService);
  }

  // UI state
  bool isSidebarOpen = true;

  // Ollama Connection State
  bool isOllamaConnected = false;
  bool isLoadingModels = false;
  String? connectionError;
  List<OllamaModel> models = [];
  String? selectedModel;
  String? embeddingModel;

  // Documents State
  final List<ProcessedDocument> documents = [];
  bool isProcessingDocs = false;
  double docProcessingProgress = 0.0;
  String docProcessingStatus = '';

  // RAG Configuration
  double temperature = 0.7;
  int topK = 4;
  double denseWeight = 0.5;
  String baseUrl = 'http://127.0.0.1:11434';

  // Chat State
  final List<ChatMessage> chatHistory = [];
  bool isGenerating = false;
  StreamSubscription<String>? _activeStreamSub;
  Timer? _uiThrottleTimer;
  String _pendingTokenBuffer = '';

  int get totalIndexedChunks => searchService.totalChunks;
  bool get hasDocuments => documents.isNotEmpty && totalIndexedChunks > 0;

  void toggleSidebar() {
    isSidebarOpen = !isSidebarOpen;
    notifyListeners();
  }

  Future<void> init() async {
    await refreshModels();
  }

  void updateBaseUrl(String newUrl) {
    if (newUrl.trim().isEmpty) return;
    baseUrl = newUrl.trim();
    ollamaService.baseUrl = baseUrl;
    refreshModels();
  }

  /// Automatically detect all installed Ollama models and select fastest default
  Future<void> refreshModels() async {
    isLoadingModels = true;
    connectionError = null;
    notifyListeners();

    try {
      final healthy = await ollamaService.checkHealth();
      isOllamaConnected = healthy;

      if (!healthy) {
        connectionError = 'Cannot reach Ollama at $baseUrl. Ensure Ollama is running.';
        models = [];
        isLoadingModels = false;
        notifyListeners();
        return;
      }

      final fetchedModels = await ollamaService.getInstalledModels();
      models = fetchedModels;

      if (models.isNotEmpty) {
        final modelNames = models.map((m) => m.name).toList();

        // Auto-select fastest generative model if current is unset
        if (selectedModel == null || !modelNames.contains(selectedModel)) {
          // Prefer lightning-fast small models first (e.g. qwen3:0.6b, deepseek-r1:1.5b)
          final fastModel = models.firstWhere(
            (m) => m.name.contains('0.6b') || m.name.contains('0.5b') || m.name.contains('1.5b'),
            orElse: () {
              final nonEmbed = models.where((m) => !m.isEmbeddingModel).toList();
              return nonEmbed.isNotEmpty ? nonEmbed.first : models.first;
            },
          );
          selectedModel = fastModel.name;
        }

        // Auto-detect dedicated embedding model (e.g. nomic-embed-text)
        final embedCandidates = models.where((m) => m.isEmbeddingModel).toList();
        if (embedCandidates.isNotEmpty) {
          embeddingModel = embedCandidates.first.name;
        } else {
          embeddingModel = selectedModel;
        }
      }
    } catch (e) {
      isOllamaConnected = false;
      connectionError = e.toString();
      models = [];
    } finally {
      isLoadingModels = false;
      notifyListeners();
    }
  }

  void setSelectedModel(String? model) {
    selectedModel = model;
    notifyListeners();
  }

  void setEmbeddingModel(String? model) {
    embeddingModel = model;
    notifyListeners();
  }

  void setTemperature(double val) {
    temperature = val;
    notifyListeners();
  }

  void setTopK(int val) {
    topK = val;
    notifyListeners();
  }

  void setDenseWeight(double val) {
    denseWeight = val;
    notifyListeners();
  }

  /// Pick PDF and text documents and index them in high-speed batches
  Future<void> pickAndProcessFiles() async {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
    );

    if (pickedFiles.isEmpty) {
      return;
    }

    isProcessingDocs = true;
    docProcessingProgress = 0.0;
    docProcessingStatus = 'Preparing documents...';
    notifyListeners();

    final int totalFiles = pickedFiles.length;
    int successCount = 0;
    final stopwatch = Stopwatch()..start();

    for (int fileIdx = 0; fileIdx < totalFiles; fileIdx++) {
      final file = pickedFiles[fileIdx];
      final filePath = file.path;
      if (filePath == null) continue;

      final fileName = file.name;

      try {
        searchService.removeChunksForDoc(fileName);
        documents.removeWhere((d) => d.fileName == fileName);

        final chunks = await documentProcessor.processFile(
          filePath: filePath,
          fileName: fileName,
          embeddingModel: embeddingModel,
          onProgress: (p, s) {
            final overall = (fileIdx + p) / totalFiles;
            docProcessingProgress = overall;
            docProcessingStatus = '[$fileName] $s';
            notifyListeners();
          },
        );

        if (chunks.isNotEmpty) {
          searchService.addChunks(chunks);
          final maxPage = chunks.map((c) => c.pageNumber).fold(1, (a, b) => a > b ? a : b);
          documents.add(ProcessedDocument(
            fileName: fileName,
            filePath: filePath,
            pageCount: maxPage,
            chunkCount: chunks.length,
          ));
          successCount++;
        }
      } catch (e) {
        docProcessingStatus = 'Error processing $fileName: $e';
      }
    }

    stopwatch.stop();
    isProcessingDocs = false;
    final sec = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    docProcessingStatus = successCount > 0
        ? '⚡ Ready in ${sec}s! ($totalIndexedChunks chunks indexed across $successCount files)'
        : 'Failed to process selected documents.';
    notifyListeners();
  }

  void removeDocument(String fileName) {
    searchService.removeChunksForDoc(fileName);
    documents.removeWhere((d) => d.fileName == fileName);
    notifyListeners();
  }

  void clearAllDocuments() {
    searchService.clearAll();
    documents.clear();
    notifyListeners();
  }

  void clearChat() {
    stopGeneration();
    chatHistory.clear();
    knowledgeGraphService.clearCache();
    notifyListeners();
  }

  /// High-speed Hybrid RAG query execution with streaming buffer
  Future<void> sendMessage(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || selectedModel == null || isGenerating) return;

    chatHistory.add(ChatMessage(
      role: MessageRole.user,
      content: trimmed,
    ));

    final assistantMsg = ChatMessage(
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
    );
    chatHistory.add(assistantMsg);

    isGenerating = true;
    _pendingTokenBuffer = '';
    notifyListeners();

    try {
      List<SearchResult> relevantChunks = [];
      final searchStopwatch = Stopwatch()..start();

      if (hasDocuments) {
        relevantChunks = await searchService.search(
          query: trimmed,
          embeddingModel: embeddingModel,
          topK: topK,
          denseWeight: denseWeight,
        );
      }
      searchStopwatch.stop();
      assistantMsg.retrievalDurationMs = searchStopwatch.elapsedMilliseconds;

      String promptToUse = trimmed;
      String systemPromptToUse = kFallbackSystemPrompt;

      if (relevantChunks.isNotEmpty) {
        assistantMsg.sources = relevantChunks;

        final buffer = StringBuffer();
        buffer.writeln('Context Information:');
        for (int i = 0; i < relevantChunks.length; i++) {
          final res = relevantChunks[i];
          buffer.writeln('--- [Source ${i + 1}: ${res.chunk.docName} (Page ${res.chunk.pageNumber})] ---');
          buffer.writeln(res.chunk.text);
          buffer.writeln();
        }
        buffer.writeln('Question: $trimmed');
        promptToUse = buffer.toString();
        systemPromptToUse = kRagSystemPrompt.trim();
      } else {
        if (hasDocuments) {
          assistantMsg.isFallback = true;
        }
        systemPromptToUse = kFallbackSystemPrompt.trim();
      }

      final List<Map<String, String>> messages = [
        {'role': 'system', 'content': systemPromptToUse},
      ];

      for (int i = 0; i < chatHistory.length - 1; i++) {
        final m = chatHistory[i];
        if (m.content.isNotEmpty) {
          messages.add({
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.content,
          });
        }
      }

      if (messages.isNotEmpty && messages.last['role'] == 'user') {
        messages.last['content'] = promptToUse;
      }

      final genStopwatch = Stopwatch()..start();

      // UI Throttled Stream Dispatcher (Smooth 120 FPS rendering without stutter)
      _uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 35), (_) {
        if (_pendingTokenBuffer.isNotEmpty) {
          assistantMsg.content += _pendingTokenBuffer;
          _pendingTokenBuffer = '';
          notifyListeners();
        }
      });

      final stream = ollamaService.chatStream(
        model: selectedModel!,
        messages: messages,
        temperature: temperature,
        keepAlive: '30m',
      );

      _activeStreamSub = stream.listen(
        (chunk) {
          _pendingTokenBuffer += chunk;
          assistantMsg.tokenCount++;
        },
        onError: (err) {
          _flushBuffer(assistantMsg);
          assistantMsg.content += '\n\n**Generation Error:** $err';
          assistantMsg.isStreaming = false;
          isGenerating = false;
          genStopwatch.stop();
          _stopThrottleTimer();
          notifyListeners();
        },
        onDone: () {
          _flushBuffer(assistantMsg);
          genStopwatch.stop();
          assistantMsg.generationDurationMs = genStopwatch.elapsedMilliseconds;
          assistantMsg.isStreaming = false;
          isGenerating = false;
          _stopThrottleTimer();
          _activeStreamSub = null;
          notifyListeners();
        },
      );
    } catch (e) {
      assistantMsg.content = 'I apologize, but an error occurred while processing: $e';
      assistantMsg.isStreaming = false;
      isGenerating = false;
      _stopThrottleTimer();
      notifyListeners();
    }
  }

  void _flushBuffer(ChatMessage msg) {
    if (_pendingTokenBuffer.isNotEmpty) {
      msg.content += _pendingTokenBuffer;
      _pendingTokenBuffer = '';
    }
  }

  void _stopThrottleTimer() {
    _uiThrottleTimer?.cancel();
    _uiThrottleTimer = null;
  }

  void stopGeneration() {
    _stopThrottleTimer();
    if (_activeStreamSub != null) {
      _activeStreamSub?.cancel();
      _activeStreamSub = null;
    }
    if (chatHistory.isNotEmpty && chatHistory.last.isStreaming) {
      _flushBuffer(chatHistory.last);
      chatHistory.last.isStreaming = false;
    }
    isGenerating = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopThrottleTimer();
    stopGeneration();
    ollamaService.dispose();
    super.dispose();
  }
}
