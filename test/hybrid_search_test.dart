import 'package:flutter_test/flutter_test.dart';
import 'package:local_hybrid_search_rag/models/document_chunk.dart';
import 'package:local_hybrid_search_rag/services/hybrid_search_service.dart';
import 'package:local_hybrid_search_rag/services/ollama_service.dart';

void main() {
  group('Hybrid Search Tests', () {
    late OllamaService ollamaService;
    late HybridSearchService searchService;

    setUp(() {
      ollamaService = OllamaService();
      searchService = HybridSearchService(ollamaService: ollamaService);
    });

    test('BM25 and Hybrid Search retrieval returns relevant chunk', () async {
      final chunk1 = DocumentChunk(
        id: 'c1',
        docName: 'doc1.pdf',
        pageNumber: 1,
        chunkIndex: 0,
        text: 'Flutter is an open-source UI software development kit created by Google for cross-platform apps.',
        embedding: OllamaService.computeHashEmbedding('Flutter is an open-source UI software development kit created by Google'),
      );

      final chunk2 = DocumentChunk(
        id: 'c2',
        docName: 'doc2.pdf',
        pageNumber: 1,
        chunkIndex: 0,
        text: 'The solar system consists of the Sun and the astronomical objects bound to it by gravity.',
        embedding: OllamaService.computeHashEmbedding('The solar system consists of the Sun and planets'),
      );

      searchService.addChunks([chunk1, chunk2]);
      expect(searchService.totalChunks, 2);

      final results = await searchService.search(
        query: 'What is Flutter SDK by Google?',
        topK: 2,
      );

      expect(results.isNotEmpty, true);
      expect(results.first.chunk.id, 'c1');
      expect(results.first.sparseScore > 0, true);
    });

    test('Unrelated query returns empty results to allow general knowledge fallback', () async {
      final chunk = DocumentChunk(
        id: 'c1',
        docName: 'tech.pdf',
        pageNumber: 1,
        chunkIndex: 0,
        text: 'Kubernetes orchestration manages containerized workloads and services declaratively.',
        embedding: OllamaService.computeHashEmbedding('Kubernetes orchestration containerized workloads'),
      );

      searchService.addChunks([chunk]);

      // Query has zero keyword match and zero semantic similarity to Kubernetes
      final results = await searchService.search(
        query: 'How to bake sourdough bread with yeast and flour?',
        topK: 2,
      );

      expect(results.isEmpty, true);
    });
  });
}
