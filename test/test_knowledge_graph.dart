import 'package:flutter_test/flutter_test.dart';
import 'package:local_hybrid_search_rag/models/chat_message.dart';
import 'package:local_hybrid_search_rag/models/document_chunk.dart';
import 'package:local_hybrid_search_rag/models/knowledge_graph.dart';
import 'package:local_hybrid_search_rag/services/knowledge_graph_service.dart';
import 'package:local_hybrid_search_rag/services/ollama_service.dart';

void main() {
  group('KnowledgeGraph Model Tests', () {
    test('Calculates node degrees and finds connections accurately', () {
      final nodeA = GraphNode(id: 'hybrid_search', label: 'Hybrid Search', category: NodeCategory.technology);
      final nodeB = GraphNode(id: 'bm25', label: 'BM25', category: NodeCategory.technology);
      final nodeC = GraphNode(id: 'vectors', label: 'Dense Vectors', category: NodeCategory.concept);

      final edge1 = const GraphEdge(sourceId: 'bm25', targetId: 'hybrid_search', label: 'combines with');
      final edge2 = const GraphEdge(sourceId: 'vectors', targetId: 'hybrid_search', label: 'merges into');

      final graph = KnowledgeGraph(
        nodes: [nodeA, nodeB, nodeC],
        edges: [edge1, edge2],
        topicSummary: 'Hybrid search architecture',
      );

      expect(graph.nodes.length, 3);
      expect(graph.edges.length, 2);

      // Hybrid Search connects to both BM25 and vectors -> degree 2
      expect(nodeA.degree, 2);
      expect(nodeB.degree, 1);
      expect(nodeC.degree, 1);

      final hybridEdges = graph.getEdgesForNode('hybrid_search');
      expect(hybridEdges.length, 2);
    });

    test('Generates valid Mermaid markdown', () {
      final nodeA = GraphNode(id: 'ollama', label: 'Ollama Engine', category: NodeCategory.technology);
      final nodeB = GraphNode(id: 'deepseek', label: 'DeepSeek Model', category: NodeCategory.technology);
      final edge = const GraphEdge(sourceId: 'ollama', targetId: 'deepseek', label: 'runs');

      final graph = KnowledgeGraph(nodes: [nodeA, nodeB], edges: [edge]);
      final mermaid = graph.toMermaid();

      expect(mermaid.contains('graph TD'), isTrue);
      expect(mermaid.contains('ollama["Ollama Engine"]'), isTrue);
      expect(mermaid.contains('deepseek["DeepSeek Model"]'), isTrue);
      expect(mermaid.contains('ollama -->|"runs"| deepseek'), isTrue);

      final pipelineMermaid = graph.toPipelineMermaid();
      expect(pipelineMermaid.contains('flowchart TD'), isTrue);
      expect(pipelineMermaid.contains('Vector Search'), isTrue);
      expect(pipelineMermaid.contains('Knowledge Graph Search'), isTrue);
    });

    test('Generates valid JSON with nodes and edges', () {
      final node = GraphNode(id: 'rrf', label: 'RRF', category: NodeCategory.process);
      final graph = KnowledgeGraph(nodes: [node], edges: []);
      final jsonStr = graph.toJsonString();

      expect(jsonStr.contains('"id": "rrf"'), isTrue);
      expect(jsonStr.contains('"category": "process"'), isTrue);
      expect(jsonStr.contains('"nodeCount": 1'), isTrue);
    });

    test('Generates self-contained standalone HTML visualizer with dual formats', () {
      final nodeA = GraphNode(id: 'n1', label: 'Node 1');
      final nodeB = GraphNode(id: 'n2', label: 'Node 2');
      final edge = const GraphEdge(sourceId: 'n1', targetId: 'n2', label: 'links');

      final graph = KnowledgeGraph(nodes: [nodeA, nodeB], edges: [edge]);
      final html = graph.toStandaloneHtml();

      expect(html.contains('<!DOCTYPE html>'), isTrue);
      expect(html.contains('d3.forceSimulation'), isTrue);
      expect(html.contains('VISLABS'), isTrue);
      expect(html.contains('svg-radial'), isTrue);
      expect(html.contains('Graph RAG vs Vector RAG'), isTrue);
    });
  });

  group('KnowledgeGraphService Caching & Heuristic Extraction Tests', () {
    late KnowledgeGraphService service;

    setUp(() {
      service = KnowledgeGraphService(ollamaService: OllamaService());
    });

    test('Extracts semantic graph from chat conversation heuristic', () async {
      final chat = [
        ChatMessage(
          role: MessageRole.user,
          content: 'How does Hybrid Search combine BM25 and vector embeddings in Ollama?',
        ),
        ChatMessage(
          role: MessageRole.assistant,
          content: 'Hybrid Search queries documents using BM25 sparse lexical tokens and dense vector embeddings from Ollama, then scores them with Reciprocal Rank Fusion.',
        ),
      ];

      final graph = await service.extractGraph(history: chat);
      expect(graph.isNotEmpty, isTrue);
      expect(graph.nodes.length, greaterThanOrEqualTo(2));

      // Verify domain entities were detected
      final labels = graph.nodes.map((n) => n.label.toLowerCase()).toList();
      expect(labels.any((l) => l.contains('bm25') || l.contains('hybrid search') || l.contains('ollama')), isTrue);
    });

    test('Caches graph and serves from cache instantly on identical chat', () async {
      final chat = [
        ChatMessage(
          role: MessageRole.user,
          content: 'Explain RRF ranking algorithm in local search',
        ),
        ChatMessage(
          role: MessageRole.assistant,
          content: 'Reciprocal Rank Fusion combines sparse and dense ranks.',
        ),
      ];

      final hash = service.computeChatHash(chat);
      expect(service.hasCachedGraph(chat), isFalse);

      final graph1 = await service.extractGraph(history: chat);
      expect(service.hasCachedGraph(chat), isTrue);

      final graph2 = await service.extractGraph(history: chat);
      // Reference should be identical
      expect(identical(graph1, graph2), isTrue);

      // Force refresh regenerates
      final graph3 = await service.extractGraph(history: chat, forceRefresh: true);
      expect(graph3.sourceHash, hash);

      // Clear cache works
      service.clearCache();
      expect(service.hasCachedGraph(chat), isFalse);
    });

    test('Builds Neo4j Bloom style chunk and concept mesh from documents', () async {
      final chunks = [
        DocumentChunk(
          id: 'c1',
          docName: 'rag_paper.pdf',
          pageNumber: 1,
          chunkIndex: 0,
          text: 'BM25 sparse ranking and dense vector embeddings merge with Reciprocal Rank Fusion.',
        ),
      ];

      final graph = await service.extractGraph(history: [], indexedChunks: chunks);
      expect(graph.isNotEmpty, isTrue);
      expect(graph.nodes.any((n) => n.category == NodeCategory.chunk), isTrue);
      expect(graph.nodes.any((n) => n.category == NodeCategory.concept), isTrue);
      expect(graph.nodes.any((n) => n.category == NodeCategory.document), isTrue);
      expect(graph.edges.any((e) => e.label == 'MENTIONS_CONCEPT'), isTrue);
    });
  });
}
