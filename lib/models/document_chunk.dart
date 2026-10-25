class DocumentChunk {
  final String id;
  final String docName;
  final int pageNumber;
  final int chunkIndex;
  final String text;
  List<double> embedding;
  Map<String, int> termFrequencies;
  int wordCount;

  static const Set<String> stopWords = {
    'a', 'about', 'above', 'after', 'again', 'against', 'all', 'am', 'an', 'and', 'any', 'are',
    'as', 'at', 'be', 'because', 'been', 'before', 'being', 'below', 'between', 'both', 'but',
    'by', 'can', 'did', 'do', 'does', 'doing', 'down', 'during', 'each', 'few', 'for', 'from',
    'further', 'had', 'has', 'have', 'having', 'he', 'her', 'here', 'hers', 'him', 'his', 'how',
    'i', 'if', 'in', 'into', 'is', 'it', 'its', 'just', 'me', 'more', 'most', 'my', 'no', 'nor',
    'not', 'now', 'of', 'off', 'on', 'once', 'only', 'or', 'other', 'our', 'out', 'over', 'own',
    'same', 'she', 'should', 'so', 'some', 'such', 'than', 'that', 'the', 'their', 'them', 'then',
    'there', 'these', 'they', 'this', 'those', 'through', 'to', 'too', 'under', 'until', 'up',
    'very', 'was', 'we', 'were', 'what', 'when', 'where', 'which', 'while', 'who', 'whom', 'why',
    'with', 'you', 'your'
  };

  DocumentChunk({
    required this.id,
    required this.docName,
    required this.pageNumber,
    required this.chunkIndex,
    required this.text,
    this.embedding = const [],
    Map<String, int>? termFrequencies,
    int? wordCount,
  })  : termFrequencies = termFrequencies ?? computeTermFrequencies(text),
        wordCount = wordCount ?? countWords(text);

  static Map<String, int> computeTermFrequencies(String text) {
    final Map<String, int> tf = {};
    final tokens = tokenize(text);
    for (final token in tokens) {
      tf[token] = (tf[token] ?? 0) + 1;
    }
    return tf;
  }

  static int countWords(String text) {
    final tokens = tokenize(text, filterStopWords: false);
    return tokens.isNotEmpty ? tokens.length : 1;
  }

  static List<String> tokenize(String text, {bool filterStopWords = true}) {
    final rawTokens = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1 || RegExp(r'^\d+$').hasMatch(t))
        .toList();

    if (filterStopWords) {
      final filtered = rawTokens.where((t) => !stopWords.contains(t)).toList();
      return filtered.isNotEmpty ? filtered : rawTokens;
    }
    return rawTokens;
  }
}

class SearchResult {
  final DocumentChunk chunk;
  final double denseScore;
  final double sparseScore;
  final double hybridScore;
  final int rank;

  SearchResult({
    required this.chunk,
    required this.denseScore,
    required this.sparseScore,
    required this.hybridScore,
    required this.rank,
  });
}
