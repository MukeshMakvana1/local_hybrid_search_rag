import 'dart:convert';
import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/document_chunk.dart';
import 'ollama_service.dart';

class ProcessedDocument {
  final String fileName;
  final String filePath;
  final int pageCount;
  final int chunkCount;
  final DateTime processedAt;

  ProcessedDocument({
    required this.fileName,
    required this.filePath,
    required this.pageCount,
    required this.chunkCount,
    DateTime? processedAt,
  }) : processedAt = processedAt ?? DateTime.now();
}

class DocumentProcessor {
  final OllamaService ollamaService;

  DocumentProcessor({required this.ollamaService});

  /// Process a single file (PDF or TXT/MD), extract text, chunk it, and batch-embed
  Future<List<DocumentChunk>> processFile({
    required String filePath,
    required String fileName,
    String? embeddingModel,
    void Function(double progress, String status)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    final lowerName = fileName.toLowerCase();
    final List<Map<String, dynamic>> rawPages = [];

    onProgress?.call(0.1, 'Reading file content...');

    if (lowerName.endsWith('.pdf')) {
      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      try {
        final int pageCount = document.pages.count;
        final PdfTextExtractor extractor = PdfTextExtractor(document);

        for (int i = 0; i < pageCount; i++) {
          final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
          if (text.trim().isNotEmpty) {
            rawPages.add({
              'pageNumber': i + 1,
              'text': text,
            });
          }
        }
      } finally {
        document.dispose();
      }
    } else {
      // Plain text or Markdown file with robust malformed-character handling
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      rawPages.add({
        'pageNumber': 1,
        'text': content,
      });
    }

    onProgress?.call(0.25, 'Segmenting text into semantic chunks...');

    final List<DocumentChunk> chunks = [];
    int globalChunkIndex = 0;

    for (final page in rawPages) {
      final int pageNum = page['pageNumber'] as int;
      final String pageText = page['text'] as String;

      final textSegments = splitIntoChunks(pageText, chunkSize: 500, overlap: 60);

      for (final segment in textSegments) {
        if (segment.trim().length < 15) continue;

        final chunk = DocumentChunk(
          id: '${fileName}_p${pageNum}_c$globalChunkIndex',
          docName: fileName,
          pageNumber: pageNum,
          chunkIndex: globalChunkIndex,
          text: segment.trim(),
        );
        chunks.add(chunk);
        globalChunkIndex++;
      }
    }

    if (chunks.isEmpty) {
      return [];
    }

    // High-speed BATCH embedding (16 chunks per call)
    const int batchSize = 16;
    final int totalChunks = chunks.length;

    for (int i = 0; i < totalChunks; i += batchSize) {
      final end = (i + batchSize < totalChunks) ? i + batchSize : totalChunks;
      final batchChunks = chunks.sublist(i, end);
      final batchTexts = batchChunks.map((c) => c.text).toList();

      final currentBatch = (i ~/ batchSize) + 1;
      final totalBatches = (totalChunks / batchSize).ceil();
      final double progress = 0.3 + (0.7 * (end / totalChunks));

      onProgress?.call(
        progress,
        'Batch vectorizing ($currentBatch/$totalBatches • $end/$totalChunks chunks)...',
      );

      try {
        final embeddings = await ollamaService.getBatchEmbeddings(
          batchTexts,
          model: embeddingModel,
        );

        for (int j = 0; j < batchChunks.length; j++) {
          if (j < embeddings.length) {
            batchChunks[j].embedding = embeddings[j];
          } else {
            batchChunks[j].embedding = OllamaService.computeHashEmbedding(batchChunks[j].text);
          }
        }
      } catch (_) {
        for (final chunk in batchChunks) {
          chunk.embedding = OllamaService.computeHashEmbedding(chunk.text);
        }
      }
    }

    onProgress?.call(1.0, 'Indexed $totalChunks chunks in $fileName');
    return chunks;
  }

  /// Sentence-aware text chunking with sliding overlap and bounded chunk size
  List<String> splitIntoChunks(String text, {int chunkSize = 500, int overlap = 60}) {
    final clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final paragraphs = clean.split(RegExp(r'\n{2,}'));
    final List<String> chunks = [];
    String currentChunk = '';

    for (final paragraph in paragraphs) {
      final p = paragraph.trim();
      if (p.isEmpty) continue;

      if (currentChunk.isEmpty) {
        currentChunk = p;
      } else if (currentChunk.length + p.length + 1 <= chunkSize) {
        currentChunk += '\n\n$p';
      } else {
        final sentences = p.split(RegExp(r'(?<=[.?!])\s+'));
        for (final s in sentences) {
          final trimmedSentence = s.trim();
          if (trimmedSentence.isEmpty) continue;

          // If a single sentence exceeds chunkSize, slice it into sub-chunks
          if (trimmedSentence.length > chunkSize) {
            if (currentChunk.isNotEmpty) {
              chunks.add(currentChunk.trim());
              currentChunk = '';
            }
            int start = 0;
            while (start < trimmedSentence.length) {
              final end = (start + chunkSize < trimmedSentence.length)
                  ? start + chunkSize
                  : trimmedSentence.length;
              chunks.add(trimmedSentence.substring(start, end).trim());
              start = (end < trimmedSentence.length) ? end - overlap : end;
            }
            continue;
          }

          if (currentChunk.isEmpty) {
            currentChunk = trimmedSentence;
          } else if (currentChunk.length + trimmedSentence.length + 1 <= chunkSize) {
            currentChunk += ' $trimmedSentence';
          } else {
            chunks.add(currentChunk.trim());
            if (currentChunk.length > overlap) {
              final overlapText = currentChunk.substring(currentChunk.length - overlap).trim();
              currentChunk = '$overlapText $trimmedSentence';
            } else {
              currentChunk = trimmedSentence;
            }
          }
        }
      }
    }

    if (currentChunk.trim().isNotEmpty) {
      chunks.add(currentChunk.trim());
    }

    return chunks;
  }
}
