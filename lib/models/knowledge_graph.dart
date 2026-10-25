import 'dart:convert';
import 'package:flutter/material.dart';

/// Categories for entities in the Knowledge Graph (Neo4j Bloom / Graph RAG style)
enum NodeCategory {
  chunk,
  concept,
  document,
  technology,
  process,
  metric,
  source,
  general;

  Color get color {
    switch (this) {
      case NodeCategory.chunk:
        return const Color(0xFF6366F1); // Periwinkle Blue for chunks
      case NodeCategory.concept:
        return const Color(0xFFEC4899); // Vibrant Hot Pink for concepts (Bloom style)
      case NodeCategory.document:
        return const Color(0xFF38BDF8); // Sky Blue for documents
      case NodeCategory.technology:
        return const Color(0xFF6366F1);
      case NodeCategory.process:
        return const Color(0xFF10B981);
      case NodeCategory.metric:
        return const Color(0xFFF59E0B);
      case NodeCategory.source:
        return const Color(0xFF06B6D4);
      case NodeCategory.general:
        return const Color(0xFFA855F7);
    }
  }

  String get label {
    switch (this) {
      case NodeCategory.chunk:
        return 'chunk';
      case NodeCategory.concept:
        return 'concept';
      case NodeCategory.document:
        return 'document';
      case NodeCategory.technology:
        return 'technology';
      case NodeCategory.process:
        return 'process';
      case NodeCategory.metric:
        return 'metric';
      case NodeCategory.source:
        return 'source';
      case NodeCategory.general:
        return 'general';
    }
  }
}

/// A node in the knowledge graph representing an entity or concept
class GraphNode {
  final String id;
  final String label;
  final NodeCategory category;
  final int mentionCount;
  int degree;
  bool isHub;
  int badgeCount;

  // Visual simulation coordinates
  double x;
  double y;
  double vx;
  double vy;
  bool isPinned;

  GraphNode({
    required this.id,
    required this.label,
    this.category = NodeCategory.general,
    this.mentionCount = 1,
    this.degree = 0,
    this.isHub = false,
    this.badgeCount = 0,
    this.x = 0.0,
    this.y = 0.0,
    this.vx = 0.0,
    this.vy = 0.0,
    this.isPinned = false,
  });

  Color get color {
    if (category == NodeCategory.concept) {
      return const Color(0xFFEC4899); // Vibrant Hot Pink for concepts (Bloom style)
    } else if (category == NodeCategory.chunk) {
      return const Color(0xFF6366F1); // Periwinkle Blue for chunks
    } else if (category == NodeCategory.document) {
      return const Color(0xFF38BDF8); // Sky Blue for documents
    }
    if (isHub) {
      return const Color(0xFFD946EF); // Neon Magenta/Purple for Central Hub
    }
    return const Color(0xFF2DD4BF);
  }

  double get radius {
    if (category == NodeCategory.chunk) return 8.0;
    if (category == NodeCategory.concept) return 5.5;
    if (category == NodeCategory.document) return 11.0;
    return isHub ? 26.0 : (16.0 + (degree * 1.5).clamp(0.0, 14.0));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'category': category.name,
        'degree': degree,
        'mentionCount': mentionCount,
        'isHub': isHub,
        'badgeCount': badgeCount,
      };

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    final catName = json['category']?.toString().toLowerCase() ?? 'general';
    final cat = NodeCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == catName,
      orElse: () => NodeCategory.general,
    );

    return GraphNode(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? json['id']?.toString() ?? '',
      category: cat,
      degree: json['degree'] is int ? json['degree'] as int : 0,
      mentionCount: json['mentionCount'] is int ? json['mentionCount'] as int : 1,
      isHub: json['isHub'] == true,
      badgeCount: json['badgeCount'] is int ? json['badgeCount'] as int : 0,
    );
  }
}

/// A directed edge in the knowledge graph representing a relationship
class GraphEdge {
  final String sourceId;
  final String targetId;
  final String label;
  final double weight;

  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.label,
    this.weight = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'source': sourceId,
        'target': targetId,
        'label': label,
        'weight': weight,
      };

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      sourceId: json['source']?.toString() ?? json['sourceId']?.toString() ?? '',
      targetId: json['target']?.toString() ?? json['targetId']?.toString() ?? '',
      label: json['label']?.toString() ?? json['relation']?.toString() ?? 'relates to',
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// The entire Knowledge Graph with dual-format export helpers
class KnowledgeGraph {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final DateTime generatedAt;
  final String sourceHash;
  final String? topicSummary;

  KnowledgeGraph({
    required this.nodes,
    required this.edges,
    DateTime? generatedAt,
    this.sourceHash = '',
    this.topicSummary,
  }) : generatedAt = generatedAt ?? DateTime.now() {
    _recalculateDegrees();
  }

  void _recalculateDegrees() {
    final Map<String, int> degreeMap = {};
    for (final node in nodes) {
      degreeMap[node.id] = 0;
      node.isHub = false;
    }
    for (final edge in edges) {
      degreeMap[edge.sourceId] = (degreeMap[edge.sourceId] ?? 0) + 1;
      degreeMap[edge.targetId] = (degreeMap[edge.targetId] ?? 0) + 1;
    }
    for (final node in nodes) {
      node.degree = degreeMap[node.id] ?? 0;
      node.badgeCount = node.degree;
    }

    // Designate the most connected node as central hub
    if (nodes.isNotEmpty) {
      GraphNode top = nodes.first;
      for (final n in nodes) {
        if (n.degree > top.degree) {
          top = n;
        }
      }
      top.isHub = true;
    }
  }

  bool get isEmpty => nodes.isEmpty;
  bool get isNotEmpty => nodes.isNotEmpty;

  GraphNode? get hubNode {
    try {
      return nodes.firstWhere((n) => n.isHub);
    } catch (_) {
      return nodes.isNotEmpty ? nodes.first : null;
    }
  }

  GraphNode? findNode(String id) {
    try {
      return nodes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  List<GraphEdge> getEdgesForNode(String nodeId) {
    return edges.where((e) => e.sourceId == nodeId || e.targetId == nodeId).toList();
  }

  /// Convert graph to JSON string
  String toJsonString({bool pretty = true}) {
    final data = {
      'generatedAt': generatedAt.toIso8601String(),
      'sourceHash': sourceHash,
      'topicSummary': topicSummary ?? 'Chat Knowledge Graph',
      'nodeCount': nodes.length,
      'edgeCount': edges.length,
      'hubId': hubNode?.id,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
    };
    return pretty ? const JsonEncoder.withIndent('  ').convert(data) : jsonEncode(data);
  }

  /// Convert graph to Mermaid.js diagram format
  String toMermaid() {
    final buffer = StringBuffer();
    buffer.writeln('```mermaid');
    buffer.writeln('graph TD');
    buffer.writeln('  %% Styles & Themes');
    buffer.writeln('  classDef hub fill:#701a75,stroke:#d946ef,stroke-width:3px,color:#fff;');
    buffer.writeln('  classDef satellite fill:#134e4a,stroke:#2dd4bf,stroke-width:2px,color:#fff;');
    buffer.writeln('  classDef tech fill:#312e81,stroke:#6366f1,stroke-width:2px,color:#fff;');
    buffer.writeln('');

    String safeId(String id) => id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

    for (final node in nodes) {
      final nid = safeId(node.id);
      final cleanLabel = node.label.replaceAll('"', "'");
      final cls = node.isHub ? 'hub' : 'satellite';
      buffer.writeln('  $nid["$cleanLabel"]:::$cls');
    }

    buffer.writeln('');
    for (final edge in edges) {
      final s = safeId(edge.sourceId);
      final t = safeId(edge.targetId);
      final cleanRel = edge.label.replaceAll('"', "'");
      if (cleanRel.isNotEmpty) {
        buffer.writeln('  $s -->|"$cleanRel"| $t');
      } else {
        buffer.writeln('  $s --> $t');
      }
    }

    buffer.writeln('```');
    return buffer.toString();
  }

  /// Mermaid flowchart for the second format: Graph RAG vs Vector RAG architecture pipeline
  String toPipelineMermaid({String query = 'User Query'}) {
    final cleanQuery = query.replaceAll('"', "'");
    return '''```mermaid
flowchart TD
    Q(["$cleanQuery"])
    
    subgraph VectorSearch ["Vector Search (Lexical + Dense)"]
      VE1(["Embedding"]) --> VE2["Embeddings"]
      VE2 --> VE3(["Retrieve"])
      VE3 --> VS[("Vector Store / BM25")]
      VS --> TOP["Top N Chunks"]
    end
    
    subgraph GraphSearch ["Knowledge Graph Search"]
      GE1(["Extract Entity"]) --> GE2["Entities"]
      GE2 --> GE3(["Retrieve"])
      GE3 --> GS[("Graph Store / Triples")]
      GS --> ER["Entity and Relationship"]
    end
    
    Q --> VE1
    Q --> GE1
    TOP --> GEN["Generate (Synthesis)"]
    ER --> GEN
    
    style Q fill:#1e293b,stroke:#94a3b8,color:#fff
    style VE1 fill:#064e3b,stroke:#10b981,color:#fff
    style VE2 fill:#022c22,stroke:#10b981,color:#fff
    style VE3 fill:#064e3b,stroke:#10b981,color:#fff
    style VS fill:#047857,stroke:#34d399,color:#fff
    style TOP fill:#065f46,stroke:#6ee7b7,color:#fff
    
    style GE1 fill:#1e3a8a,stroke:#38bdf8,color:#fff
    style GE2 fill:#0f172a,stroke:#38bdf8,color:#fff
    style GE3 fill:#1e3a8a,stroke:#38bdf8,color:#fff
    style GS fill:#0284c7,stroke:#7dd3fc,color:#fff
    style ER fill:#0369a1,stroke:#bae6fd,color:#fff
    
    style GEN fill:#052e16,stroke:#22c55e,stroke-width:2px,color:#fff
```''';
  }

  /// Generate a standalone, self-contained modern HTML visualizer with D3 force simulation,
  /// dark obsidian aesthetics, interactive pan/zoom, physics dragging, mini-map radar,
  /// and BOTH format views (VISLABS Starburst + Graph RAG vs Vector RAG Pipeline Flow).
  String toStandaloneHtml() {
    final jsonGraph = toJsonString(pretty: false);

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Knowledge Graph Visualizer - Dual Format</title>
  <style>
    :root {
      --bg: #090d16;
      --surface: #111827;
      --surface-light: #1f293d;
      --border: #232e4a;
      --primary: #6366f1;
      --mint: #2dd4bf;
      --magenta: #d946ef;
      --cyan: #06b6d4;
      --emerald: #10b981;
      --text: #f8fafc;
      --text-muted: #94a3b8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      overflow: hidden;
      height: 100vh;
      width: 100vw;
    }

    /* Top VISLABS style Header */
    #topbar {
      position: absolute;
      top: 14px;
      left: 16px;
      right: 16px;
      z-index: 100;
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: rgba(17, 24, 39, 0.9);
      backdrop-filter: blur(14px);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 10px 18px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.6);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .brand-logo {
      font-size: 16px;
      font-weight: 900;
      letter-spacing: 0.1em;
      color: #fff;
    }
    .brand-dot {
      color: var(--cyan);
    }
    .doc-title-pill {
      display: flex;
      align-items: center;
      gap: 6px;
      background: rgba(31, 41, 61, 0.7);
      border: 1px solid var(--border);
      padding: 4px 12px;
      border-radius: 8px;
      font-size: 12px;
      color: var(--text-muted);
    }

    /* Dual Format Switcher Tabs */
    .view-switcher {
      display: flex;
      background: rgba(9, 13, 22, 0.9);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 3px;
      gap: 4px;
    }
    .tab-btn {
      background: transparent;
      border: none;
      color: var(--text-muted);
      font-size: 12px;
      font-weight: 600;
      padding: 6px 14px;
      border-radius: 7px;
      cursor: pointer;
      transition: all 0.2s;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .tab-btn.active {
      background: var(--primary);
      color: #fff;
      box-shadow: 0 2px 8px rgba(99, 102, 241, 0.5);
    }

    .top-actions {
      display: flex;
      gap: 8px;
      align-items: center;
    }
    .btn-action {
      background: rgba(31, 41, 61, 0.8);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 6px 12px;
      border-radius: 8px;
      font-size: 11px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
    }
    .btn-action:hover {
      background: var(--primary);
      border-color: var(--primary);
    }

    /* Views Container */
    #views-container {
      width: 100vw;
      height: 100vh;
      position: relative;
    }
    .view-panel {
      width: 100%;
      height: 100%;
      position: absolute;
      top: 0;
      left: 0;
      display: none;
    }
    .view-panel.active {
      display: block;
    }

    /* Mini-Map Radar (VISLABS style) */
    #radar-minimap {
      position: absolute;
      bottom: 20px;
      right: 20px;
      z-index: 100;
      width: 220px;
      background: rgba(17, 24, 39, 0.92);
      backdrop-filter: blur(14px);
      border: 1px solid var(--border);
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 10px 30px rgba(0,0,0,0.6);
    }
    #minimap-canvas {
      width: 100%;
      height: 140px;
      background: #090d16;
      display: block;
    }
    .radar-controls {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 12px;
      border-top: 1px solid var(--border);
      font-size: 11px;
      color: var(--text-muted);
    }
    .radar-btn {
      background: none;
      border: none;
      color: var(--text-muted);
      cursor: pointer;
      font-size: 13px;
      padding: 2px 6px;
    }
    .radar-btn:hover { color: #fff; }

    /* SVG Canvas */
    #svg-radial {
      width: 100vw;
      height: 100vh;
      display: block;
      cursor: grab;
    }
    #svg-radial:active {
      cursor: grabbing;
    }

    /* Format 2: Pipeline view styling */
    #pipeline-scroll {
      width: 100vw;
      height: 100vh;
      overflow: auto;
      padding-top: 90px;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .pipeline-title {
      font-size: 20px;
      font-weight: 700;
      margin-bottom: 28px;
      color: #fff;
      text-align: center;
      letter-spacing: -0.01em;
    }
    .pipeline-container {
      display: flex;
      flex-direction: column;
      align-items: center;
      position: relative;
      max-width: 900px;
      width: 100%;
      padding-bottom: 60px;
    }
    .user-query-node {
      display: flex;
      flex-direction: column;
      align-items: center;
      margin-bottom: 24px;
    }
    .user-avatar-circle {
      width: 52px;
      height: 52px;
      border-radius: 50%;
      background: #1e293b;
      border: 2px solid #94a3b8;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
    }
    .dual-tracks {
      display: flex;
      justify-content: space-around;
      width: 100%;
      gap: 60px;
      margin-bottom: 30px;
    }
    .track-col {
      flex: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 16px;
    }
    .track-header {
      font-size: 14px;
      font-weight: 700;
      margin-bottom: 8px;
    }
    .node-oval {
      padding: 8px 24px;
      border-radius: 20px;
      font-size: 13px;
      font-weight: 600;
      text-align: center;
    }
    .node-rect {
      padding: 10px 24px;
      border-radius: 6px;
      font-size: 13px;
      font-weight: 600;
      text-align: center;
      min-width: 150px;
    }
    .node-cylinder {
      width: 120px;
      height: 60px;
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 12px;
      font-weight: 700;
      text-align: center;
      border: 2px dashed;
    }
    .arrow-down {
      color: #64748b;
      font-size: 18px;
      line-height: 1;
    }
    .generate-converge {
      width: 240px;
      padding: 14px;
      border-radius: 8px;
      background: #064e3b;
      border: 2px solid #10b981;
      text-align: center;
      font-size: 15px;
      font-weight: 800;
      color: #ecfdf5;
      box-shadow: 0 8px 24px rgba(16, 185, 129, 0.35);
    }
  </style>
</head>
<body>
  <!-- Header Bar -->
  <div id="topbar">
    <div class="brand">
      <div class="brand-logo">VISLABS<span class="brand-dot">.</span></div>
      <div class="doc-title-pill">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/></svg>
        <span id="doc-topic">Hybrid RAG Knowledge Graph</span>
      </div>
    </div>

    <!-- Dual Format View Switcher -->
    <div class="view-switcher">
      <button class="tab-btn active" id="btn-radial" onclick="switchView('radial')">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><circle cx="19" cy="5" r="2"/><circle cx="5" cy="19" r="2"/><line x1="14" y1="10" x2="17.5" y2="6.5"/><line x1="10" y1="14" x2="6.5" y2="17.5"/></svg>
        Radial Topology
      </button>
      <button class="tab-btn" id="btn-pipeline" onclick="switchView('pipeline')">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="8.5" y="14" width="7" height="7"/><path d="M6.5 10v2a2 2 0 0 0 2 2h7a2 2 0 0 0 2-2v-2"/></svg>
        Graph RAG vs Vector RAG Flow
      </button>
    </div>

    <div class="top-actions">
      <button class="btn-action" onclick="resetRadialZoom()">Center View</button>
      <button class="btn-action" onclick="downloadJSON()">Export JSON</button>
    </div>
  </div>

  <!-- Views Container -->
  <div id="views-container">
    <!-- Format 1: VISLABS Radial Starburst Topology -->
    <div class="view-panel active" id="view-radial">
      <svg id="svg-radial"></svg>

      <!-- Mini-Map Radar -->
      <div id="radar-minimap">
        <canvas id="minimap-canvas" width="220" height="140"></canvas>
        <div class="radar-controls">
          <button class="radar-btn" onclick="zoomRadial(0.8)">-</button>
          <span id="zoom-indicator">100%</span>
          <button class="radar-btn" onclick="zoomRadial(1.25)">+</button>
          <button class="radar-btn" onclick="resetRadialZoom()">Fit</button>
        </div>
      </div>
    </div>

    <!-- Format 2: Hierarchical Graph RAG vs Vector RAG Architecture Flow -->
    <div class="view-panel" id="view-pipeline">
      <div id="pipeline-scroll">
        <h2 class="pipeline-title">Retrieval and Generation: Graph RAG vs Vector RAG</h2>
        <div class="pipeline-container">
          <!-- Top Query Node -->
          <div class="user-query-node">
            <div class="user-avatar-circle">👤</div>
            <div style="font-size: 13px; font-weight: 700; margin-top: 6px;">Query</div>
            <div class="arrow-down" style="margin-top: 4px;">↓</div>
          </div>

          <!-- Dual Tracks -->
          <div class="dual-tracks">
            <!-- Left Branch: Vector Search -->
            <div class="track-col">
              <div class="track-header" style="color: #34d399;">Vector Search</div>
              <div class="node-oval" style="background: #064e3b; border: 1.5px solid #10b981; color: #a7f3d0;">Embedding</div>
              <div class="arrow-down">↓</div>
              <div class="node-rect" style="background: #022c22; border: 1.5px solid #10b981; color: #6ee7b7;">Embeddings</div>
              <div class="arrow-down">↓</div>
              <div class="node-oval" style="background: #064e3b; border: 1.5px solid #10b981; color: #a7f3d0;">Retrieve</div>
              <div class="arrow-down">↓</div>
              <div class="node-cylinder" style="background: #064e3b; border-color: #34d399; color: #ecfdf5;">Vector Store<br><span style="font-size: 10px; font-weight: normal; color: #6ee7b7;">Dense + BM25</span></div>
              <div class="arrow-down">↓</div>
              <div class="node-rect" style="background: #065f46; border: 1.5px solid #34d399; color: #ecfdf5;">Top N Chunks</div>
            </div>

            <!-- Right Branch: Knowledge Graph Search -->
            <div class="track-col">
              <div class="track-header" style="color: #38bdf8;">Knowledge Graph Search</div>
              <div class="node-oval" style="background: #1e3a8a; border: 1.5px solid #38bdf8; color: #bae6fd;">Extract Entity</div>
              <div class="arrow-down">↓</div>
              <div class="node-rect" style="background: #0f172a; border: 1.5px solid #38bdf8; color: #7dd3fc;">Entities</div>
              <div class="arrow-down">↓</div>
              <div class="node-oval" style="background: #1e3a8a; border: 1.5px solid #38bdf8; color: #bae6fd;">Retrieve</div>
              <div class="arrow-down">↓</div>
              <div class="node-cylinder" style="background: #0c4a6e; border-color: #38bdf8; color: #f0f9ff;">Graph Store<br><span style="font-size: 10px; font-weight: normal; color: #7dd3fc;">Entities + Relations</span></div>
              <div class="arrow-down">↓</div>
              <div class="node-rect" style="background: #0284c7; border: 1.5px solid #7dd3fc; color: #f0f9ff;">Entity and Relationship</div>
            </div>
          </div>

          <!-- Bottom Converge -->
          <div class="arrow-down" style="margin-bottom: 8px;">↘ &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; ↙</div>
          <div class="generate-converge">Generate</div>
          <div style="font-size: 11px; color: var(--text-muted); margin-top: 8px;">Synthesizes hybrid vector chunks + knowledge graph facts with Ollama</div>
        </div>
      </div>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/d3@7/dist/d3.min.js"></script>
  <script>
    const data = $jsonGraph;

    let currentZoom = 1.0;
    const svg = d3.select("#svg-radial");
    let width = window.innerWidth;
    let height = window.innerHeight;

    const g = svg.append("g");

    const zoom = d3.zoom()
      .scaleExtent([0.2, 3.5])
      .on("zoom", (event) => {
        g.attr("transform", event.transform);
        currentZoom = event.transform.k;
        document.getElementById("zoom-indicator").innerText = Math.round(currentZoom * 100) + "%";
        drawMinimap();
      });
    svg.call(zoom);

    // Format 1: VISLABS Starburst simulation
    const links = data.edges.map(e => ({ source: e.source, target: e.target, label: e.label || "" }));

    const simulation = d3.forceSimulation(data.nodes)
      .force("link", d3.forceLink(links).id(d => d.id).distance(120))
      .force("charge", d3.forceManyBody().strength(-400))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius(d => d.isHub ? 45 : 32));

    // Links with Spoke Relation Labels
    const linkGroup = g.append("g").attr("class", "links");
    const linkLines = linkGroup.selectAll("line")
      .data(links)
      .join("line")
      .attr("stroke", "#334155")
      .attr("stroke-width", 1.8)
      .attr("stroke-opacity", 0.7);

    // Spoke Pill Chips for relation text
    const edgeLabels = g.append("g").attr("class", "edge-labels")
      .selectAll("g")
      .data(links)
      .join("g");

    edgeLabels.append("rect")
      .attr("rx", 4)
      .attr("ry", 4)
      .attr("fill", "#0f172a")
      .attr("stroke", "#1e293b")
      .attr("stroke-width", 1)
      .attr("height", 16);

    edgeLabels.append("text")
      .attr("fill", "#94a3b8")
      .attr("font-size", 9)
      .attr("font-weight", "600")
      .attr("text-anchor", "middle")
      .attr("dy", 11)
      .text(d => d.label);

    edgeLabels.each(function(d) {
      const textNode = d3.select(this).select("text").node();
      const textWidth = textNode.getComputedTextLength();
      d3.select(this).select("rect")
        .attr("width", textWidth + 10)
        .attr("x", -((textWidth + 10) / 2));
    });

    // Node Groups
    const nodeGroup = g.append("g").attr("class", "nodes");
    const nodes = nodeGroup.selectAll("g")
      .data(data.nodes)
      .join("g")
      .call(d3.drag()
        .on("start", dragstarted)
        .on("drag", dragged)
        .on("end", dragended));

    // Hub Dotted Orbit
    nodes.filter(d => d.isHub).append("circle")
      .attr("r", 38)
      .attr("fill", "none")
      .attr("stroke", "#d946ef")
      .attr("stroke-width", 1.5)
      .attr("stroke-dasharray", "4,4")
      .attr("opacity", 0.7);

    // Node Circles (Magenta for Hub, Mint for Satellites)
    nodes.append("circle")
      .attr("r", d => d.isHub ? 26 : (16 + Math.min(14, (d.degree || 0) * 1.5)))
      .attr("fill", d => d.isHub ? "#d946ef" : "#2dd4bf")
      .attr("stroke", d => d.isHub ? "#f0abfc" : "#5eead4")
      .attr("stroke-width", d => d.isHub ? 3 : 2)
      .attr("style", d => d.isHub ? "filter: drop-shadow(0 0 16px rgba(217,70,239,0.8));" : "filter: drop-shadow(0 0 10px rgba(45,212,191,0.5));");

    // Center Core
    nodes.append("circle")
      .attr("r", d => d.isHub ? 6 : 4)
      .attr("fill", "#ffffff");

    // Satellite Badge Count (top-right badge like '0', '1')
    nodes.filter(d => !d.isHub).append("circle")
      .attr("cx", 14)
      .attr("cy", -14)
      .attr("r", 7)
      .attr("fill", "#0f172a")
      .attr("stroke", "#2dd4bf")
      .attr("stroke-width", 1);

    nodes.filter(d => !d.isHub).append("text")
      .attr("x", 14)
      .attr("y", -11)
      .attr("fill", "#2dd4bf")
      .attr("font-size", 8)
      .attr("font-weight", "bold")
      .attr("text-anchor", "middle")
      .text(d => d.badgeCount || 0);

    // Dark Pill Label Badge Under Node
    const pill = nodes.append("g").attr("class", "pill-label");
    pill.append("rect")
      .attr("rx", 6)
      .attr("ry", 6)
      .attr("fill", "#0f172a")
      .attr("stroke", d => d.isHub ? "rgba(217,70,239,0.5)" : "#1e293b")
      .attr("stroke-width", 1)
      .attr("height", 20);

    pill.append("text")
      .attr("fill", "#f8fafc")
      .attr("font-size", 10)
      .attr("font-weight", "600")
      .attr("text-anchor", "middle")
      .attr("dy", 14)
      .text(d => d.label);

    pill.each(function(d) {
      const textNode = d3.select(this).select("text").node();
      const textWidth = textNode.getComputedTextLength();
      const r = d.isHub ? 26 : (16 + Math.min(14, (d.degree || 0) * 1.5));
      d3.select(this).attr("transform", `translate(0, \${r + 8})`);
      d3.select(this).select("rect")
        .attr("width", textWidth + 14)
        .attr("x", -((textWidth + 14) / 2));
    });

    simulation.on("tick", () => {
      linkLines
        .attr("x1", d => d.source.x)
        .attr("y1", d => d.source.y)
        .attr("x2", d => d.target.x)
        .attr("y2", d => d.target.y);

      edgeLabels.attr("transform", d => `translate(\${(d.source.x + d.target.x)/2}, \${(d.source.y + d.target.y)/2})`);
      nodes.attr("transform", d => `translate(\${d.x},\${d.y})`);
      drawMinimap();
    });

    function dragstarted(event, d) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      d.fx = d.x;
      d.fy = d.y;
    }
    function dragged(event, d) {
      d.fx = event.x;
      d.fy = event.y;
    }
    function dragended(event, d) {
      if (!event.active) simulation.alphaTarget(0);
      d.fx = null;
      d.fy = null;
    }

    // Mini-Map Radar Drawing
    function drawMinimap() {
      const canvas = document.getElementById("minimap-canvas");
      if (!canvas) return;
      const ctx = canvas.getContext("2d");
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      ctx.save();
      ctx.translate(canvas.width / 2, canvas.height / 2);
      ctx.scale(0.12, 0.12);

      // Draw links on minimap
      ctx.strokeStyle = "#334155";
      ctx.lineWidth = 4;
      links.forEach(l => {
        if (l.source && l.target) {
          ctx.beginPath();
          ctx.moveTo(l.source.x, l.source.y);
          ctx.lineTo(l.target.x, l.target.y);
          ctx.stroke();
        }
      });

      // Draw nodes on minimap
      data.nodes.forEach(n => {
        ctx.fillStyle = n.isHub ? "#d946ef" : "#2dd4bf";
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.isHub ? 20 : 12, 0, Math.PI * 2);
        ctx.fill();
      });

      ctx.restore();
    }

    // View Switching
    function switchView(mode) {
      document.getElementById("view-radial").classList.toggle("active", mode === "radial");
      document.getElementById("view-pipeline").classList.toggle("active", mode === "pipeline");
      document.getElementById("btn-radial").classList.toggle("active", mode === "radial");
      document.getElementById("btn-pipeline").classList.toggle("active", mode === "pipeline");
      document.getElementById("radar-minimap").style.display = mode === "radial" ? "block" : "none";
    }

    function zoomRadial(factor) {
      svg.transition().duration(250).call(zoom.scaleBy, factor);
    }

    function resetRadialZoom() {
      svg.transition().duration(500).call(
        zoom.transform,
        d3.zoomIdentity.translate(0, 0).scale(1)
      );
      simulation.alpha(0.6).restart();
    }

    function downloadJSON() {
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "knowledge_graph.json";
      a.click();
      URL.revokeObjectURL(url);
    }
  </script>
</body>
</html>''';
  }
}
