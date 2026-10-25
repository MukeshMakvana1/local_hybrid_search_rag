import 'dart:math';
import '../models/document_chunk.dart';
import 'ollama_service.dart';

class HybridSearchService {
  final OllamaService ollamaService;
  final List<DocumentChunk> _chunks = [];

  HybridSearchService({required this.ollamaService});

  List<DocumentChunk> get allChunks => List.unmodifiable(_chunks);
  int get totalChunks => _chunks.length;

  void addChunks(List<DocumentChunk> newChunks) {
    _chunks.addAll(newChunks);
  }

  void removeChunksForDoc(String docName) {
    _chunks.removeWhere((c) => c.docName == docName);
  }

  void clearAll() {
    _chunks.clear();
  }

  /// Perform Hybrid Search combining BM25 Sparse Search and Vector Dense Search
  Future<List<SearchResult>> search({
    required String query,
    String? embeddingModel,
    int topK = 5,
    double denseWeight = 0.5,
    double minScoreThreshold = 0.005,
  }) async {
    if (_chunks.isEmpty || query.trim().isEmpty) {
      return [];
    }

    final queryTokens = DocumentChunk.tokenize(query);
    if (queryTokens.isEmpty) {
      return [];
    }

    // 1. BM25 Sparse Search
    final Map<String, double> bm25Scores = _computeBM25Scores(queryTokens);

    // 2. Vector Dense Search (Cosine Similarity)
    List<double> queryEmbedding;
    try {
      queryEmbedding = await ollamaService.getEmbedding(
        query,
        model: embeddingModel,
      );
    } catch (_) {
      queryEmbedding = OllamaService.computeHashEmbedding(query);
    }

    final Map<String, double> denseScores = {};
    for (final chunk in _chunks) {
      if (chunk.embedding.isNotEmpty && queryEmbedding.isNotEmpty) {
        final sim = _cosineSimilarity(queryEmbedding, chunk.embedding);
        denseScores[chunk.id] = max(0.0, sim);
      } else {
        denseScores[chunk.id] = 0.0;
      }
    }

    // 3. Rank both lists
    final sparseRanked = _chunks.map((c) => c.id).toList()
      ..sort((a, b) => (bm25Scores[b] ?? 0.0).compareTo(bm25Scores[a] ?? 0.0));

    final denseRanked = _chunks.map((c) => c.id).toList()
      ..sort((a, b) => (denseScores[b] ?? 0.0).compareTo(denseScores[a] ?? 0.0));

    // Maps chunkId -> 1-based rank
    final Map<String, int> sparseRankMap = {};
    for (int i = 0; i < sparseRanked.length; i++) {
      sparseRankMap[sparseRanked[i]] = i + 1;
    }

    final Map<String, int> denseRankMap = {};
    for (int i = 0; i < denseRanked.length; i++) {
      denseRankMap[denseRanked[i]] = i + 1;
    }

    // 4. Reciprocal Rank Fusion (RRF) + Normalized Weighted Score
    const double kRrf = 60.0;
    final double sparseWeight = 1.0 - denseWeight;

    // Normalize raw scores to [0, 1] for balanced combination
    final double maxSparse = bm25Scores.values.fold(0.0, max);
    final double maxDense = denseScores.values.fold(0.0, max);

    final List<SearchResult> results = [];

    for (final chunk in _chunks) {
      final sScore = bm25Scores[chunk.id] ?? 0.0;
      final dScore = denseScores[chunk.id] ?? 0.0;

      // Filter out chunks that have neither keyword match nor significant semantic similarity
      final bool hasKeywordMatch = sScore > 0.0;
      final bool hasSemanticMatch = dScore >= 0.22;
      if (!hasKeywordMatch && !hasSemanticMatch) {
        continue;
      }

      final sRank = sparseRankMap[chunk.id] ?? _chunks.length;
      final dRank = denseRankMap[chunk.id] ?? _chunks.length;

      // Standard RRF formula
      final rrfScore = (denseWeight / (kRrf + dRank)) + (sparseWeight / (kRrf + sRank));

      // Normalized direct score fusion
      final normSparse = maxSparse > 0 ? (sScore / maxSparse) : 0.0;
      final normDense = maxDense > 0 ? (dScore / maxDense) : 0.0;
      final combinedLinear = (denseWeight * normDense) + (sparseWeight * normSparse);

      // Blended hybrid score
      final finalScore = (rrfScore * 100.0) + (combinedLinear * 0.5);

      if (finalScore >= minScoreThreshold) {
        results.add(SearchResult(
          chunk: chunk,
          denseScore: dScore,
          sparseScore: sScore,
          hybridScore: finalScore,
          rank: 0,
        ));
      }
    }

    // Sort by hybrid score descending
    results.sort((a, b) => b.hybridScore.compareTo(a.hybridScore));

    // Assign final ranks and slice to topK
    final topResults = results.take(topK).toList();
    final List<SearchResult> rankedTopResults = [];
    for (int i = 0; i < topResults.length; i++) {
      final r = topResults[i];
      rankedTopResults.add(SearchResult(
        chunk: r.chunk,
        denseScore: r.denseScore,
        sparseScore: r.sparseScore,
        hybridScore: r.hybridScore,
        rank: i + 1,
      ));
    }

    return rankedTopResults;
  }

  /// BM25 scoring algorithm
  Map<String, double> _computeBM25Scores(List<String> queryTokens) {
    final Map<String, double> scores = {};
    final int nDocs = _chunks.length;
    if (nDocs == 0) return scores;

    // 1. Calculate Average Document Length
    double totalWords = 0;
    for (final chunk in _chunks) {
      totalWords += chunk.wordCount;
    }
    final double avgdl = totalWords / nDocs;

    // 2. Calculate Document Frequencies (DF) for each query token
    final Map<String, int> df = {};
    for (final token in queryTokens) {
      int count = 0;
      for (final chunk in _chunks) {
        if (chunk.termFrequencies.containsKey(token)) {
          count++;
        }
      }
      df[token] = count;
    }

    // 3. Calculate BM25 for each chunk
    const double k1 = 1.5;
    const double b = 0.75;

    for (final chunk in _chunks) {
      double score = 0.0;
      final double docLen = chunk.wordCount.toDouble();

      for (final token in queryTokens) {
        final int tf = chunk.termFrequencies[token] ?? 0;
        if (tf == 0) continue;

        final int docFreq = df[token] ?? 0;
        // IDF with Robertson-Spärck Jones smoothing
        final double idf = log(1.0 + (nDocs - docFreq + 0.5) / (docFreq + 0.5));

        // Term frequency saturation & length normalization
        final double numerator = tf * (k1 + 1.0);
        final double denominator = tf + k1 * (1.0 - b + b * (docLen / (avgdl > 0 ? avgdl : 1.0)));

        score += idf * (numerator / denominator);
      }

      scores[chunk.id] = max(0.0, score);
    }

    return scores;
  }

  /// Fast vector similarity calculation
  double _cosineSimilarity(List<double> vecA, List<double> vecB) {
    if (vecA.isEmpty || vecB.isEmpty) return 0.0;
    final int len = min(vecA.length, vecB.length);
    double dot = 0.0;
    for (int i = 0; i < len; i++) {
      dot += vecA[i] * vecB[i];
    }
    return dot;
  }
}
