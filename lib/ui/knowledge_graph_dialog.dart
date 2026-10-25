import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/knowledge_graph.dart';
import '../services/app_state.dart';

enum KnowledgeGraphViewMode {
  bloomMesh,       // Neo4j Bloom / Graph RAG Constellation Mesh (Screenshot match)
  radialStarburst, // VISLABS Hub-and-Spoke Radial Topology
  pipelineFlow,    // Graph RAG vs Vector RAG Dual Track Flow
}

class KnowledgeGraphDialog extends StatefulWidget {
  final AppState state;

  const KnowledgeGraphDialog({super.key, required this.state});

  static Future<void> show(BuildContext context, AppState state) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => KnowledgeGraphDialog(state: state),
    );
  }

  @override
  State<KnowledgeGraphDialog> createState() => _KnowledgeGraphDialogState();
}

class _KnowledgeGraphDialogState extends State<KnowledgeGraphDialog>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  KnowledgeGraph? _graph;
  bool _isLoading = true;
  String? _errorMessage;
  GraphNode? _selectedNode;

  // View Mode: Bloom Constellation Mesh is the primary default
  KnowledgeGraphViewMode _viewMode = KnowledgeGraphViewMode.bloomMesh;

  // Viewport transformation (Pan & Zoom)
  Offset _panOffset = Offset.zero;
  double _zoomScale = 1.0;

  // Dragging node
  GraphNode? _draggedNode;

  // Simulation step counter for cooling
  int _simulationSteps = 0;
  bool _isPhysicsRunning = true;

  // Bloom Inspector Toggles
  bool _showChunks = true;
  bool _showConcepts = true;
  bool _showDocuments = true;
  bool _showMentionsConceptEdges = true;
  bool _showPartOfEdges = true;
  bool _showSimilarToEdges = true;
  bool _grayRecords = true;
  bool _straightEdges = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadGraph(forceRefresh: false);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadGraph({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final graph = await widget.state.knowledgeGraphService.extractGraph(
        history: widget.state.chatHistory,
        indexedChunks: widget.state.searchService.allChunks,
        model: widget.state.selectedModel,
        forceRefresh: forceRefresh,
      );

      _initializePositions(graph);

      if (mounted) {
        setState(() {
          _graph = graph;
          _isLoading = false;
          _simulationSteps = 0;
        });
        if (!_ticker.isActive && _isPhysicsRunning) {
          _ticker.start();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to generate knowledge graph: $e';
        });
      }
    }
  }

  /// Initialize nodes in dense multi-lobe constellation layout (Bloom style)
  void _initializePositions(KnowledgeGraph graph) {
    if (graph.nodes.isEmpty) return;

    final random = Random(42);
    final chunks = graph.nodes.where((n) => n.category == NodeCategory.chunk).toList();
    final concepts = graph.nodes.where((n) => n.category == NodeCategory.concept).toList();
    final docs = graph.nodes.where((n) => n.category == NodeCategory.document).toList();

    // Place document roots at wide centers
    for (int i = 0; i < docs.length; i++) {
      final angle = (i * 2 * pi) / max(1, docs.length);
      docs[i].x = cos(angle) * 160.0;
      docs[i].y = sin(angle) * 160.0;
    }

    // Place chunk hubs in two large lobes (Cluster A & Cluster B)
    for (int i = 0; i < chunks.length; i++) {
      final isLobeA = i % 2 == 0;
      final lobeCenter = isLobeA ? const Offset(-150, -50) : const Offset(150, 50);
      final angle = random.nextDouble() * 2 * pi;
      final dist = 35.0 + random.nextDouble() * 110.0;

      chunks[i].x = lobeCenter.dx + cos(angle) * dist;
      chunks[i].y = lobeCenter.dy + sin(angle) * dist;
      chunks[i].vx = 0;
      chunks[i].vy = 0;
    }

    // Place concepts orbiting closely around connected chunks like dense petals
    final edgeMap = <String, List<String>>{};
    for (final e in graph.edges) {
      edgeMap.putIfAbsent(e.sourceId, () => []).add(e.targetId);
    }

    for (final concept in concepts) {
      String? parentChunkId;
      for (final entry in edgeMap.entries) {
        if (entry.value.contains(concept.id)) {
          parentChunkId = entry.key;
          break;
        }
      }

      final parent = graph.findNode(parentChunkId ?? '');
      final pPos = parent != null ? Offset(parent.x, parent.y) : Offset.zero;
      final angle = random.nextDouble() * 2 * pi;
      final dist = 24.0 + random.nextDouble() * 45.0;

      concept.x = pPos.dx + cos(angle) * dist;
      concept.y = pPos.dy + sin(angle) * dist;
      concept.vx = 0;
      concept.vy = 0;
    }
  }

  void _onTick(Duration elapsed) {
    if (_graph == null || _isLoading || _graph!.nodes.isEmpty || !_isPhysicsRunning) return;
    if (_viewMode == KnowledgeGraphViewMode.pipelineFlow) return;

    // Simulation cooling after 160 steps to save 100% CPU when stabilized
    _simulationSteps++;
    if (_simulationSteps > 160 && _draggedNode == null) {
      _ticker.stop();
      return;
    }

    final nodes = _graph!.nodes;
    final edges = _graph!.edges;
    final nodeMap = {for (var n in nodes) n.id: n};

    const double repulsionK = 2200.0;
    const double springK = 0.05;
    const double springLength = 48.0;
    const double centeringK = 0.003;
    const double damping = 0.84;

    // 1. Repulsion between nearby nodes
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < min(nodes.length, i + 25); j++) {
        final a = nodes[i];
        final b = nodes[j];
        double dx = b.x - a.x;
        double dy = b.y - a.y;
        double dist = sqrt(dx * dx + dy * dy);
        if (dist < 1.0) {
          dx = 1.0;
          dist = 1.0;
        }
        if (dist > 180.0) continue;

        final force = repulsionK / (dist * dist);
        final fx = (dx / dist) * force;
        final fy = (dy / dist) * force;

        if (!a.isPinned) {
          a.vx -= fx;
          a.vy -= fy;
        }
        if (!b.isPinned) {
          b.vx += fx;
          b.vy += fy;
        }
      }
    }

    // 2. Spring attraction along edges
    for (final edge in edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      final dx = tgt.x - src.x;
      final dy = tgt.y - src.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 1.0) continue;

      final delta = dist - springLength;
      final force = delta * springK;
      final fx = (dx / dist) * force;
      final fy = (dy / dist) * force;

      if (!src.isPinned) {
        src.vx += fx;
        src.vy += fy;
      }
      if (!tgt.isPinned) {
        tgt.vx -= fx;
        tgt.vy += fy;
      }
    }

    // 3. Central gravity & velocity integration
    for (final node in nodes) {
      if (node.isPinned) continue;

      node.vx -= node.x * centeringK;
      node.vy -= node.y * centeringK;

      node.vx *= damping;
      node.vy *= damping;

      node.x += node.vx;
      node.y += node.vy;
    }

    setState(() {});
  }

  void _wakePhysics() {
    _simulationSteps = 0;
    if (!_ticker.isActive && _isPhysicsRunning) {
      _ticker.start();
    }
  }

  Future<void> _downloadFile({
    required String fileName,
    required String content,
    required String mimeType,
    required String formatTitle,
  }) async {
    try {
      final bytes = Uint8List.fromList(content.codeUnits);
      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Save Knowledge Graph as $formatTitle',
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );

      if (mounted && savedUri != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E1A30),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved successfully: $fileName',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.shade700,
            content: Text('Failed to save file: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C0A14), // Neo4j Bloom deep purple-black
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF26213B)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.95),
                blurRadius: 48,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Column(
            children: [
              // Top Bar matching user screenshot
              _buildTopBar(),

              const Divider(height: 1, color: Color(0xFF1E1A30)),

              // Main Workspace
              Expanded(
                child: _isLoading
                    ? _buildLoadingState()
                    : _errorMessage != null
                        ? _buildErrorState()
                        : _buildWorkspace(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Bar with Result #1 pill, view switcher, and vibrant Hot Pink "Run query" button
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF13101F),
      child: Row(
        children: [
          // "Result #1" Pill Badge (exact match to screenshot)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A30),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF352E54)),
            ),
            child: const Text(
              'Result #1',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9)),
            ),
          ),
          const SizedBox(width: 14),

          // View Switcher Pill
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0A14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF26213B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewTab(KnowledgeGraphViewMode.bloomMesh, 'Constellation Mesh', Icons.bubble_chart_rounded),
                _buildViewTab(KnowledgeGraphViewMode.radialStarburst, 'Radial Starburst', Icons.hub_rounded),
                _buildViewTab(KnowledgeGraphViewMode.pipelineFlow, 'Graph RAG Flow', Icons.account_tree_rounded),
              ],
            ),
          ),

          const Spacer(),

          const Text(
            'Query 1',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),

          // Vibrant Hot Pink "Run query ▽" Button (Exact match from screenshot!)
          FilledButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Run query', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE8457C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 4,
            ),
            onPressed: () => _loadGraph(forceRefresh: true),
          ),
          const SizedBox(width: 10),

          // Export / Download Menu
          PopupMenuButton<String>(
            tooltip: 'Download Graph',
            icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF38BDF8)),
            color: const Color(0xFF1E1A30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFF352E54)),
            ),
            onSelected: (val) {
              if (_graph == null) return;
              if (val == 'html') {
                _downloadFile(
                  fileName: 'knowledge_graph.html',
                  content: _graph!.toStandaloneHtml(),
                  mimeType: 'text/html',
                  formatTitle: 'Standalone Interactive HTML',
                );
              } else if (val == 'json') {
                _downloadFile(
                  fileName: 'knowledge_graph.json',
                  content: _graph!.toJsonString(),
                  mimeType: 'application/json',
                  formatTitle: 'Graph Data JSON',
                );
              } else if (val == 'mermaid') {
                _downloadFile(
                  fileName: 'knowledge_graph.md',
                  content: _viewMode == KnowledgeGraphViewMode.pipelineFlow
                      ? _graph!.toPipelineMermaid()
                      : _graph!.toMermaid(),
                  mimeType: 'text/markdown',
                  formatTitle: 'Mermaid Markdown',
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'html',
                child: Row(
                  children: [
                    Icon(Icons.html_rounded, size: 16, color: Color(0xFF38BDF8)),
                    SizedBox(width: 8),
                    Text('Download Standalone HTML', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'json',
                child: Row(
                  children: [
                    Icon(Icons.data_object_rounded, size: 16, color: Color(0xFFEC4899)),
                    SizedBox(width: 8),
                    Text('Download JSON Schema', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'mermaid',
                child: Row(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 16, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Text('Download Mermaid Diagram', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(width: 4),

          // Close Dialog
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildViewTab(KnowledgeGraphViewMode mode, String title, IconData icon) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () {
        setState(() => _viewMode = mode);
        _wakePhysics();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE8457C)),
          ),
          SizedBox(height: 16),
          Text(
            'Synthesizing Bloom Constellation...',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
          const SizedBox(height: 10),
          Text(_errorMessage ?? 'Error', style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => _loadGraph(forceRefresh: true), child: const Text('Retry')),
        ],
      ),
    );
  }

  /// Main workspace layout containing canvas and docked Neo4j Bloom inspector
  Widget _buildWorkspace() {
    if (_viewMode == KnowledgeGraphViewMode.pipelineFlow) {
      return _buildPipelineFlowView();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset((constraints.maxWidth - 240) / 2, constraints.maxHeight / 2);

        return Stack(
          children: [
            // Center Canvas Area
            Positioned(
              left: 0,
              top: 0,
              right: 240, // Space reserved for docked right panel
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  final localPos = details.localFocalPoint - center - _panOffset;
                  final scaledX = localPos.dx / _zoomScale;
                  final scaledY = localPos.dy / _zoomScale;
                  final threshold = 18.0 / _zoomScale;

                  for (final node in _graph!.nodes) {
                    final dist = sqrt(pow(node.x - scaledX, 2) + pow(node.y - scaledY, 2));
                    if (dist <= node.radius + threshold) {
                      _draggedNode = node;
                      node.isPinned = true;
                      setState(() => _selectedNode = node);
                      _wakePhysics();
                      break;
                    }
                  }
                },
                onScaleUpdate: (details) {
                  if (_draggedNode != null) {
                    final localPos = details.localFocalPoint - center - _panOffset;
                    _draggedNode!.x = localPos.dx / _zoomScale;
                    _draggedNode!.y = localPos.dy / _zoomScale;
                    _wakePhysics();
                    setState(() {});
                  } else {
                    setState(() {
                      _panOffset += details.focalPointDelta;
                      _zoomScale = (_zoomScale * details.scale).clamp(0.15, 3.5);
                    });
                  }
                },
                onScaleEnd: (_) {
                  if (_draggedNode != null) {
                    _draggedNode!.isPinned = false;
                    _draggedNode = null;
                  }
                },
                onTapUp: (details) {
                  final localPos = details.localPosition - center - _panOffset;
                  final scaledX = localPos.dx / _zoomScale;
                  final scaledY = localPos.dy / _zoomScale;
                  final threshold = 18.0 / _zoomScale;

                  GraphNode? tapped;
                  for (final node in _graph!.nodes) {
                    final dist = sqrt(pow(node.x - scaledX, 2) + pow(node.y - scaledY, 2));
                    if (dist <= node.radius + threshold) {
                      tapped = node;
                      break;
                    }
                  }
                  setState(() => _selectedNode = tapped);
                },
                child: CustomPaint(
                  painter: _viewMode == KnowledgeGraphViewMode.radialStarburst
                      ? _RadialTopologyPainter(
                          graph: _graph!,
                          selectedNode: _selectedNode,
                          panOffset: _panOffset,
                          zoomScale: _zoomScale,
                          center: center,
                        )
                      : _BloomConstellationPainter(
                          graph: _graph!,
                          selectedNode: _selectedNode,
                          panOffset: _panOffset,
                          zoomScale: _zoomScale,
                          center: center,
                          showChunks: _showChunks,
                          showConcepts: _showConcepts,
                          showDocuments: _showDocuments,
                          showMentionsEdges: _showMentionsConceptEdges,
                          showPartOfEdges: _showPartOfEdges,
                          showSimilarEdges: _showSimilarToEdges,
                          grayRecords: _grayRecords,
                          straightEdges: _straightEdges,
                        ),
                ),
              ),
            ),

            // Left Floating Toolstrip (Screenshot match: Zoom, Fit, Pause/Play)
            Positioned(
              left: 14,
              top: 14,
              child: _buildLeftToolstrip(),
            ),

            // Right Inspector & Legend Panel (Exact match from user screenshot!)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 240,
              child: _buildBloomInspectorPanel(),
            ),
          ],
        );
      },
    );
  }

  /// Left vertical toolstrip matching the screenshot
  Widget _buildLeftToolstrip() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF13101F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF26213B)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom In',
            icon: const Icon(Icons.zoom_in_rounded, size: 16, color: Color(0xFF94A3B8)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => setState(() => _zoomScale = (_zoomScale * 1.25).clamp(0.15, 3.5)),
          ),
          IconButton(
            tooltip: 'Zoom Out',
            icon: const Icon(Icons.zoom_out_rounded, size: 16, color: Color(0xFF94A3B8)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => setState(() => _zoomScale = (_zoomScale * 0.8).clamp(0.15, 3.5)),
          ),
          IconButton(
            tooltip: 'Fit to screen',
            icon: const Icon(Icons.crop_free_rounded, size: 15, color: Color(0xFF94A3B8)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => setState(() {
              _panOffset = Offset.zero;
              _zoomScale = 1.0;
            }),
          ),
          IconButton(
            tooltip: _isPhysicsRunning ? 'Pause Physics' : 'Resume Physics',
            icon: Icon(
              _isPhysicsRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 16,
              color: _isPhysicsRunning ? const Color(0xFFE8457C) : const Color(0xFF10B981),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              setState(() => _isPhysicsRunning = !_isPhysicsRunning);
              if (_isPhysicsRunning) {
                _wakePhysics();
              } else {
                _ticker.stop();
              }
            },
          ),
        ],
      ),
    );
  }

  /// Right Inspector & Legend Panel (Exact replica of user screenshot!)
  Widget _buildBloomInspectorPanel() {
    final totalRecords = _graph?.nodes.length ?? 0;
    final totalEdges = _graph?.edges.length ?? 0;
    final chunkCount = _graph?.nodes.where((n) => n.category == NodeCategory.chunk).length ?? 0;
    final conceptCount = _graph?.nodes.where((n) => n.category == NodeCategory.concept).length ?? 0;
    final docCount = _graph?.nodes.where((n) => n.category == NodeCategory.document).length ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF13101F),
        border: Border(left: BorderSide(color: Color(0xFF26213B))),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Graph Stats
            const Text(
              'Graph',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFF1F5F9)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.remove_red_eye_outlined, size: 13, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text('$totalRecords records', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.polyline_rounded, size: 13, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text('$totalEdges edges', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.radio_button_unchecked, size: 13, color: Color(0xFF94A3B8)),
                SizedBox(width: 6),
                Text('0 stray records', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFF26213B)),
            const SizedBox(height: 12),

            // Section 2: Types (chunk, concept, document)
            const Text(
              'Types',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFF1F5F9)),
            ),
            const SizedBox(height: 6),
            _buildTypeRow('chunk', const Color(0xFF6366F1), chunkCount, _showChunks, (v) => setState(() => _showChunks = v!)),
            _buildTypeRow('concept', const Color(0xFFEC4899), conceptCount, _showConcepts, (v) => setState(() => _showConcepts = v!)),
            _buildTypeRow('document', const Color(0xFF38BDF8), docCount, _showDocuments, (v) => setState(() => _showDocuments = v!)),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFF26213B)),
            const SizedBox(height: 12),

            // Section 3: Edges (MENTIONS_CONCEPT, PART_OF)
            const Text(
              'Edges',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFF1F5F9)),
            ),
            const SizedBox(height: 6),
            _buildEdgeRow('MENTIONS_CONCEPT', _showMentionsConceptEdges, (v) => setState(() => _showMentionsConceptEdges = v!)),
            _buildEdgeRow('PART_OF', _showPartOfEdges, (v) => setState(() => _showPartOfEdges = v!)),
            _buildEdgeRow('SIMILAR_TO', _showSimilarToEdges, (v) => setState(() => _showSimilarToEdges = v!)),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFF26213B)),
            const SizedBox(height: 12),

            // Section 4: Appearance (Gray records, Straight edges)
            const Text(
              'Appearance',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFF1F5F9)),
            ),
            const SizedBox(height: 6),
            _buildAppearanceRow('Gray records', _grayRecords, (v) => setState(() => _grayRecords = v!)),
            _buildAppearanceRow('Straight edges', _straightEdges, (v) => setState(() => _straightEdges = v!)),

            const SizedBox(height: 16),

            // Section 5: Direct Download Graph Buttons
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('Download Graph HTML', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                minimumSize: const Size(double.infinity, 34),
              ),
              onPressed: () {
                if (_graph == null) return;
                _downloadFile(
                  fileName: 'knowledge_graph.html',
                  content: _graph!.toStandaloneHtml(),
                  mimeType: 'text/html',
                  formatTitle: 'Standalone Interactive HTML',
                );
              },
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.data_object_rounded, size: 13),
              label: const Text('Download Graph JSON', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                side: const BorderSide(color: Color(0xFF26213B)),
                minimumSize: const Size(double.infinity, 32),
              ),
              onPressed: () {
                if (_graph == null) return;
                _downloadFile(
                  fileName: 'knowledge_graph.json',
                  content: _graph!.toJsonString(),
                  mimeType: 'application/json',
                  formatTitle: 'Graph JSON',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeRow(String name, Color color, int count, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: value,
            activeColor: color,
            checkColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: onChanged,
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 11, color: Color(0xFFF1F5F9), fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _buildEdgeRow(String label, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: value,
            activeColor: const Color(0xFF6366F1),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: onChanged,
          ),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceRow(String label, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: value,
            activeColor: const Color(0xFFE8457C),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: onChanged,
          ),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFF1F5F9)),
            ),
          ),
        ],
      ),
    );
  }

  /// Format 3: Pipeline Flow View
  Widget _buildPipelineFlowView() {
    final queryText = widget.state.chatHistory.isNotEmpty
        ? widget.state.chatHistory.firstWhere((m) => m.isUser, orElse: () => widget.state.chatHistory.first).content
        : 'User Query';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              const Text(
                'Retrieval and Generation: Graph RAG vs Vector RAG',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 20),
              // Query Node
              Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0F172A),
                      border: Border.all(color: const Color(0xFF94A3B8), width: 2),
                    ),
                    child: const Center(child: Icon(Icons.person_rounded, size: 26, color: Colors.white)),
                  ),
                  const SizedBox(height: 4),
                  const Text('Query', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('"$queryText"', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF94A3B8))),
                ],
              ),
              const SizedBox(height: 16),
              // Tracks
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Vector Search', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF34D399))),
                        const SizedBox(height: 8),
                        _buildPipelineBox('Embedding', const Color(0xFF064E3B), const Color(0xFF10B981)),
                        const Icon(Icons.arrow_downward, size: 16, color: Color(0xFF64748B)),
                        _buildPipelineBox('Vector Store', const Color(0xFF064E3B), const Color(0xFF34D399)),
                        const Icon(Icons.arrow_downward, size: 16, color: Color(0xFF64748B)),
                        _buildPipelineBox('Top N Chunks', const Color(0xFF065F46), const Color(0xFF6EE7B7)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Knowledge Graph Search', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF38BDF8))),
                        const SizedBox(height: 8),
                        _buildPipelineBox('Extract Entity', const Color(0xFF1E3A8A), const Color(0xFF38BDF8)),
                        const Icon(Icons.arrow_downward, size: 16, color: Color(0xFF64748B)),
                        _buildPipelineBox('Graph Store', const Color(0xFF0C4A6E), const Color(0xFF38BDF8)),
                        const Icon(Icons.arrow_downward, size: 16, color: Color(0xFF64748B)),
                        _buildPipelineBox('Entity and Relationship', const Color(0xFF0284C7), const Color(0xFF7DD3FC)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Icon(Icons.arrow_downward_rounded, size: 24, color: Color(0xFF10B981)),
              Container(
                width: 220,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                ),
                child: const Center(
                  child: Text('Generate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineBox(String text, Color bg, Color border) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Center(
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
      ),
    );
  }
}

/// Custom Canvas Painter rendering the Neo4j Bloom / Graph RAG Constellation Mesh
class _BloomConstellationPainter extends CustomPainter {
  final KnowledgeGraph graph;
  final GraphNode? selectedNode;
  final Offset panOffset;
  final double zoomScale;
  final Offset center;
  final bool showChunks;
  final bool showConcepts;
  final bool showDocuments;
  final bool showMentionsEdges;
  final bool showPartOfEdges;
  final bool showSimilarEdges;
  final bool grayRecords;
  final bool straightEdges;

  _BloomConstellationPainter({
    required this.graph,
    required this.selectedNode,
    required this.panOffset,
    required this.zoomScale,
    required this.center,
    required this.showChunks,
    required this.showConcepts,
    required this.showDocuments,
    required this.showMentionsEdges,
    required this.showPartOfEdges,
    required this.showSimilarEdges,
    required this.grayRecords,
    required this.straightEdges,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx + panOffset.dx, center.dy + panOffset.dy);
    canvas.scale(zoomScale);

    final nodeMap = {for (var n in graph.nodes) n.id: n};

    // Find connected nodes to selected node if any
    final Set<String> connectedNodeIds = {};
    if (selectedNode != null) {
      connectedNodeIds.add(selectedNode!.id);
      for (final e in graph.edges) {
        if (e.sourceId == selectedNode!.id) connectedNodeIds.add(e.targetId);
        if (e.targetId == selectedNode!.id) connectedNodeIds.add(e.sourceId);
      }
    }

    // 1. Draw Edges
    final edgePaint = Paint()
      ..color = const Color(0xFF4A4660).withValues(alpha: 0.65)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final dimmedEdgePaint = Paint()
      ..color = const Color(0xFF26213B).withValues(alpha: 0.25)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final selectedEdgePaint = Paint()
      ..color = const Color(0xFFE8457C)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    for (final edge in graph.edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      if (edge.label == 'MENTIONS_CONCEPT' && !showMentionsEdges) continue;
      if (edge.label == 'PART_OF' && !showPartOfEdges) continue;
      if (edge.label == 'SIMILAR_TO' && !showSimilarEdges) continue;

      if (src.category == NodeCategory.chunk && !showChunks) continue;
      if (tgt.category == NodeCategory.chunk && !showChunks) continue;
      if (src.category == NodeCategory.concept && !showConcepts) continue;
      if (tgt.category == NodeCategory.concept && !showConcepts) continue;
      if (src.category == NodeCategory.document && !showDocuments) continue;
      if (tgt.category == NodeCategory.document && !showDocuments) continue;

      final isSelected = selectedNode != null &&
          (edge.sourceId == selectedNode!.id || edge.targetId == selectedNode!.id);

      final isDimmed = grayRecords && selectedNode != null && !isSelected;

      final p1 = Offset(src.x, src.y);
      final p2 = Offset(tgt.x, tgt.y);

      final p = isSelected
          ? selectedEdgePaint
          : (isDimmed ? dimmedEdgePaint : edgePaint);

      if (straightEdges) {
        canvas.drawLine(p1, p2, p);
      } else {
        final path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..quadraticBezierTo(
            (p1.dx + p2.dx) / 2 + 10,
            (p1.dy + p2.dy) / 2 - 10,
            p2.dx,
            p2.dy,
          );
        canvas.drawPath(path, p);
      }
    }

    // 2. Draw Nodes (Bloom style dense dots)
    for (final node in graph.nodes) {
      if (node.category == NodeCategory.chunk && !showChunks) continue;
      if (node.category == NodeCategory.concept && !showConcepts) continue;
      if (node.category == NodeCategory.document && !showDocuments) continue;

      final isSelected = selectedNode?.id == node.id;
      final isConnected = connectedNodeIds.contains(node.id);
      final isDimmed = grayRecords && selectedNode != null && !isSelected && !isConnected;

      final nodePos = Offset(node.x, node.y);

      Color nColor = node.color;
      if (isDimmed) {
        nColor = const Color(0xFF352E54); // Gray records dimming
      }

      // Outer glow for concepts and selected nodes
      if (!isDimmed && (node.category == NodeCategory.concept || isSelected)) {
        final glowPaint = Paint()
          ..color = nColor.withValues(alpha: isSelected ? 0.6 : 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(nodePos, node.radius + (isSelected ? 5 : 2), glowPaint);
      }

      // Circle Body
      final bodyPaint = Paint()
        ..color = nColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(nodePos, node.radius, bodyPaint);

      // Rim
      final rimPaint = Paint()
        ..color = isSelected ? Colors.white : nColor.withValues(alpha: 0.9)
        ..strokeWidth = isSelected ? 2.0 : 0.8
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(nodePos, node.radius, rimPaint);

      // Selected or Hovered Label
      if (isSelected || (zoomScale > 1.4 && !isDimmed)) {
        _drawNodeLabel(canvas, node.label, nodePos, node.radius, isSelected);
      }
    }

    canvas.restore();
  }

  void _drawNodeLabel(Canvas canvas, String label, Offset pos, double radius, bool isSelected) {
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        fontSize: isSelected ? 10 : 9,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout(maxWidth: 120);
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy + radius + 4));
  }

  @override
  bool shouldRepaint(covariant _BloomConstellationPainter oldDelegate) => true;
}

/// Custom Canvas Painter rendering Format 2 (VISLABS Hub-and-Spoke Radial Starburst)
class _RadialTopologyPainter extends CustomPainter {
  final KnowledgeGraph graph;
  final GraphNode? selectedNode;
  final Offset panOffset;
  final double zoomScale;
  final Offset center;

  _RadialTopologyPainter({
    required this.graph,
    required this.selectedNode,
    required this.panOffset,
    required this.zoomScale,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx + panOffset.dx, center.dy + panOffset.dy);
    canvas.scale(zoomScale);

    final nodeMap = {for (var n in graph.nodes) n.id: n};
    final hub = graph.hubNode;

    // Spoke lines
    final spokePaint = Paint()
      ..color = const Color(0xFF263248)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    for (final edge in graph.edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      canvas.drawLine(Offset(src.x, src.y), Offset(tgt.x, tgt.y), spokePaint);
    }

    // Hub Dotted Orbit
    if (hub != null) {
      final orbitPaint = Paint()
        ..color = const Color(0xFFD946EF).withValues(alpha: 0.6)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      _drawDashedCircle(canvas, Offset(hub.x, hub.y), 42.0, orbitPaint);
    }

    // Nodes
    for (final node in graph.nodes) {
      final pos = Offset(node.x, node.y);
      final isSelected = selectedNode?.id == node.id;

      final circlePaint = Paint()
        ..color = node.isHub ? const Color(0xFFD946EF) : const Color(0xFF2DD4BF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, node.radius, circlePaint);

      final rimPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.white70
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pos, node.radius, rimPaint);
    }

    canvas.restore();
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const dashCount = 28;
    const double step = (2 * pi) / dashCount;
    for (int i = 0; i < dashCount; i++) {
      if (i % 2 == 0) {
        final startAngle = i * step;
        final sweepAngle = step * 0.7;
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadialTopologyPainter oldDelegate) => true;
}
