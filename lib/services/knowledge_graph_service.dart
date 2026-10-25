import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/document_chunk.dart';
import '../models/knowledge_graph.dart';
import 'ollama_service.dart';

/// Service responsible for extracting, caching, and serving Knowledge Graphs from chat history and indexed chunks
class KnowledgeGraphService {
  final OllamaService ollamaService;

  // In-memory cache keyed by conversation and chunks hash
  final Map<String, KnowledgeGraph> _cache = {};

  KnowledgeGraphService({required this.ollamaService});

  /// Generate a unique fingerprint for the current chat history and documents
  String computeChatHash(List<ChatMessage> history, [List<DocumentChunk>? chunks]) {
    final buffer = StringBuffer();
    if (history.isEmpty && (chunks == null || chunks.isEmpty)) return 'empty_default';

    for (final m in history) {
      buffer.write('${m.role.name}:${m.content.length}:${m.content.hashCode};');
    }
    if (chunks != null) {
      buffer.write('chunks:${chunks.length};');
    }
    return buffer.toString().hashCode.toString();
  }

  /// Check whether a cached knowledge graph is available
  bool hasCachedGraph(List<ChatMessage> history, [List<DocumentChunk>? chunks]) {
    final hash = computeChatHash(history, chunks);
    return _cache.containsKey(hash);
  }

  /// Clear the graph cache
  void clearCache() {
    _cache.clear();
  }

  /// Extract and synthesize Knowledge Graph from chat history and document chunks with instant caching
  Future<KnowledgeGraph> extractGraph({
    required List<ChatMessage> history,
    List<DocumentChunk>? indexedChunks,
    String? model,
    bool forceRefresh = false,
  }) async {
    final hash = computeChatHash(history, indexedChunks);

    // Instant return if cached and not force refreshing
    if (!forceRefresh && _cache.containsKey(hash)) {
      debugPrint('[KnowledgeGraphService] Serving graph from instant cache (hash: $hash)');
      return _cache[hash]!;
    }

    KnowledgeGraph graph;

    // Build the rich Neo4j Bloom style Document Chunk & Concept Mesh
    if (indexedChunks != null && indexedChunks.isNotEmpty) {
      graph = _buildChunkConceptMeshFromDocuments(indexedChunks, history, hash);
    } else {
      graph = _buildChunkConceptMeshFromChat(history, hash);
    }

    // Cache the resulting graph
    _cache[hash] = graph;
    return graph;
  }

  /// Build dense Neo4j Bloom constellation mesh from indexed document chunks
  KnowledgeGraph _buildChunkConceptMeshFromDocuments(
    List<DocumentChunk> chunks,
    List<ChatMessage> history,
    String hash,
  ) {
    final Map<String, GraphNode> nodeMap = {};
    final List<GraphEdge> edges = [];
    final Set<String> edgeSet = {};

    // 1. Create Document Nodes (Sky Blue)
    final docNames = chunks.map((c) => c.docName).toSet();
    for (final doc in docNames) {
      final docId = 'doc_${doc.replaceAll(RegExp(r'[^\w\-]'), '_')}';
      nodeMap[docId] = GraphNode(
        id: docId,
        label: doc,
        category: NodeCategory.document,
      );
    }

    // 2. Sample chunks (up to 40 chunks for high density)
    final sampleChunks = chunks.length > 40 ? chunks.sublist(0, 40) : chunks;

    for (int i = 0; i < sampleChunks.length; i++) {
      final chunk = sampleChunks[i];
      final chunkId = 'chunk_${chunk.id}';
      final docId = 'doc_${chunk.docName.replaceAll(RegExp(r'[^\w\-]'), '_')}';

      // Chunk node (Periwinkle Blue)
      nodeMap[chunkId] = GraphNode(
        id: chunkId,
        label: 'Chunk ${chunk.chunkIndex + 1} (${chunk.docName})',
        category: NodeCategory.chunk,
      );

      // Edge: chunk -> doc (PART_OF)
      if (nodeMap.containsKey(docId)) {
        final edgeKey = '$chunkId->$docId';
        if (!edgeSet.contains(edgeKey)) {
          edgeSet.add(edgeKey);
          edges.add(GraphEdge(sourceId: chunkId, targetId: docId, label: 'PART_OF'));
        }
      }

      // 3. Extract salient concepts from chunk term frequencies (excluding stopwords)
      final sortedTerms = chunk.termFrequencies.entries
          .where((e) =>
              e.key.length > 3 &&
              !DocumentChunk.stopWords.contains(e.key.toLowerCase()) &&
              RegExp(r'^[a-zA-Z]+$').hasMatch(e.key))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final topTerms = sortedTerms.take(6).map((e) => e.key).toList();

      for (final term in topTerms) {
        final conceptId = 'concept_${term.toLowerCase()}';
        final cleanLabel = term.length > 1 ? '${term[0].toUpperCase()}${term.substring(1)}' : term.toUpperCase();

        nodeMap[conceptId] ??= GraphNode(
          id: conceptId,
          label: cleanLabel,
          category: NodeCategory.concept,
        );

        // Edge: chunk -> concept (MENTIONS_CONCEPT)
        final edgeKey = '$chunkId->$conceptId';
        if (!edgeSet.contains(edgeKey)) {
          edgeSet.add(edgeKey);
          edges.add(GraphEdge(
            sourceId: chunkId,
            targetId: conceptId,
            label: 'MENTIONS_CONCEPT',
          ));
        }
      }

      // 4. Connect adjacent chunks or chunks sharing document
      if (i > 0) {
        final prevChunkId = 'chunk_${sampleChunks[i - 1].id}';
        final edgeKey = '$prevChunkId->$chunkId';
        if (!edgeSet.contains(edgeKey)) {
          edgeSet.add(edgeKey);
          edges.add(GraphEdge(sourceId: prevChunkId, targetId: chunkId, label: 'SIMILAR_TO'));
        }
      }
    }

    return KnowledgeGraph(
      nodes: nodeMap.values.toList(),
      edges: edges,
      sourceHash: hash,
      topicSummary: 'Document Chunks and Extracted Concept Constellation',
    );
  }

  /// Build dense Neo4j Bloom constellation mesh from chat conversation turns
  KnowledgeGraph _buildChunkConceptMeshFromChat(
    List<ChatMessage> history,
    String hash,
  ) {
    final Map<String, GraphNode> nodeMap = {};
    final List<GraphEdge> edges = [];
    final Set<String> edgeSet = {};

    // Domain concept taxonomy
    const Map<String, List<String>> chunkTemplates = {
      'Hybrid Retrieval Pipeline': [
        'BM25 Sparse Index',
        'Dense Vector Embeddings',
        'Cosine Similarity',
        'Reciprocal Rank Fusion',
        'Score Normalization',
      ],
      'Document Ingestion & Chunking': [
        'PDF Parsing Engine',
        'Sliding Window Chunking',
        'Tokenization',
        'Term Frequency Counter',
        'Stopword Filtering',
      ],
      'Ollama Local Inference': [
        'Qwen3 Model',
        'DeepSeek R1',
        'Temperature Control',
        'Streaming Response',
        'Context Window Size',
      ],
      'Knowledge Graph Subsystem': [
        'Entity Extraction',
        'Relational Triples',
        'Bloom Constellation',
        'Force Directed Physics',
        'Graph Caching Engine',
      ],
      'Vector Similarity Engine': [
        'L2 Normalization',
        'Dot Product Score',
        'High Dimension Space',
        'Nomic Embeddings',
        'Semantic Cache',
      ],
      'Search Rank Optimization': [
        'Relevance Threshold',
        'Dense Weight Tuning',
        'Keyword Overlap',
        'RRF Reciprocal Scoring',
        'Top N Chunks Retrieval',
      ],
    };

    // Root Document Node
    const docId = 'doc_rag_system';
    nodeMap[docId] = GraphNode(
      id: docId,
      label: 'Local Hybrid RAG Knowledge Base',
      category: NodeCategory.document,
    );

    // If history has user messages, incorporate them
    for (int i = 0; i < history.length; i++) {
      final msg = history[i];
      final chunkId = 'chunk_chat_$i';

      nodeMap[chunkId] = GraphNode(
        id: chunkId,
        label: '${msg.isUser ? "User Query" : "AI Response"} #$i',
        category: NodeCategory.chunk,
      );

      edges.add(GraphEdge(sourceId: chunkId, targetId: docId, label: 'PART_OF'));

      // Extract concepts from message words
      final words = msg.content
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3 && !DocumentChunk.stopWords.contains(w.toLowerCase()))
          .take(5);

      for (final w in words) {
        final conceptId = 'concept_${w.toLowerCase()}';
        final cleanLabel = '${w[0].toUpperCase()}${w.substring(1)}';

        nodeMap[conceptId] ??= GraphNode(
          id: conceptId,
          label: cleanLabel,
          category: NodeCategory.concept,
        );

        final edgeKey = '$chunkId->$conceptId';
        if (!edgeSet.contains(edgeKey)) {
          edgeSet.add(edgeKey);
          edges.add(GraphEdge(sourceId: chunkId, targetId: conceptId, label: 'MENTIONS_CONCEPT'));
        }
      }
    }

    // Build dense system chunks to ensure rich constellation
    int chunkIdx = 0;
    String? prevChunkId;

    chunkTemplates.forEach((chunkTitle, concepts) {
      final chunkId = 'chunk_sys_$chunkIdx';
      nodeMap[chunkId] = GraphNode(
        id: chunkId,
        label: chunkTitle,
        category: NodeCategory.chunk,
      );

      edges.add(GraphEdge(sourceId: chunkId, targetId: docId, label: 'PART_OF'));

      if (prevChunkId != null) {
        final edgeKey = '$prevChunkId->$chunkId';
        if (!edgeSet.contains(edgeKey)) {
          edgeSet.add(edgeKey);
          edges.add(GraphEdge(sourceId: prevChunkId!, targetId: chunkId, label: 'SIMILAR_TO'));
        }
      }
      prevChunkId = chunkId;

      for (final c in concepts) {
        final conceptId = 'concept_${c.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
        nodeMap[conceptId] ??= GraphNode(
          id: conceptId,
          label: c,
          category: NodeCategory.concept,
        );

        final edgeKey = '$chunkId->$conceptId';
        if (!edgeSet.contains(edgeKey)) {
          edgeSet.add(edgeKey);
          edges.add(GraphEdge(sourceId: chunkId, targetId: conceptId, label: 'MENTIONS_CONCEPT'));
        }
      }
      chunkIdx++;
    });

    return KnowledgeGraph(
      nodes: nodeMap.values.toList(),
      edges: edges,
      sourceHash: hash,
      topicSummary: 'RAG Architecture and Conversation Constellation',
    );
  }
}
