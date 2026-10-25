# 🔮 Local Hybrid Search RAG & Knowledge Graph Desktop

> **A high-performance, 100% offline, privacy-first Retrieval-Augmented Generation (RAG) and interactive Knowledge Graph desktop application built with Flutter & Ollama for Windows.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Ollama](https://img.shields.io/badge/Ollama-Local_AI-000000?logo=ollama&logoColor=white)](https://ollama.com)
[![Platform](https://img.shields.io/badge/Platform-Windows_Desktop-0078D6?logo=windows&logoColor=white)](https://learn.microsoft.com/en-us/windows/apps/desktop/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
  - [1. 100% Local & Zero Cloud Exposure](#1-100-local--zero-cloud-exposure)
  - [2. Auto-Detection of Local Ollama Models](#2-auto-detection-of-local-ollama-models)
  - [3. True Hybrid Search Engine (BM25 + Dense Vectors + RRF)](#3-true-hybrid-search-engine-bm25--dense-vectors--rrf)
  - [4. Multi-PDF Ingestion & Smart Chunking](#4-multi-pdf-ingestion--smart-chunking)
  - [5. Interactive Knowledge Graph Suite (3 View Modes)](#5-interactive-knowledge-graph-suite-3-view-modes)
  - [6. Multi-Format Export & Instant Caching](#6-multi-format-export--instant-caching)
  - [7. Modern Obsidian Glassmorphism UI](#7-modern-obsidian-glassmorphism-ui)
- [Architecture & Tech Stack](#-architecture--tech-stack)
- [Directory Structure](#-directory-structure)
- [Prerequisites](#-prerequisites)
- [Installation & Quick Start](#-installation--quick-start)
- [User Guide](#-user-guide)
  - [Selecting Ollama Models](#selecting-ollama-models)
  - [Loading Documents](#loading-documents)
  - [Chatting with Hybrid RAG](#chatting-with-hybrid-rag)
  - [Generating & Exploring the Knowledge Graph](#generating--exploring-the-knowledge-graph)
  - [Exporting Graph Artifacts](#exporting-graph-artifacts)
- [RAG Algorithm & Math](#-rag-algorithm--math)
- [Testing & Quality Assurance](#-testing--quality-assurance)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)

---

## 🌟 Overview

**Local Hybrid Search RAG Assistant** is a desktop application designed to bridge the gap between large language models and proprietary knowledge bases—without relying on cloud APIs or transmitting private data.

Running locally on Windows, it combines:
1. **Dense Vector Embeddings** (capturing high-level semantic intuition),
2. **Sparse Lexical Search (BM25)** (capturing exact keywords, abbreviations, and part numbers), and
3. **Interactive Graph Topology** (exposing chunk-concept connections, document provenance, and relationship graphs).

```
   ┌─────────────────────────────────────────────────────────────┐
   │                     User Query / Prompt                     │
   └──────────────────────────────┬──────────────────────────────┘
                                  │
         ┌────────────────────────┴────────────────────────┐
         ▼                                                 ▼
┌──────────────────┐                             ┌──────────────────┐
│ Dense Embeddings │                             │   Sparse BM25    │
│ (Cosine Vector)  │                             │ (Token Frequency)│
└────────┬─────────┘                             └────────┬─────────┘
         │                                                 │
         └────────────────────────┬────────────────────────┘
                                  ▼
                     ┌─────────────────────────┐
                     │ Reciprocal Rank Fusion  │
                     │  (RRF Hybrid Scoring)   │
                     └────────────┬────────────┘
                                  ▼
                     ┌─────────────────────────┐
                     │ Top-K Chunks + Context  │
                     └────────────┬────────────┘
                                  ▼
                     ┌─────────────────────────┐
                     │   Ollama Local LLM      │
                     │  Context-Ground Answer  │
                     └────────────┬────────────┘
                                  ▼
                     ┌─────────────────────────┐
                     │ Interactive Knowledge   │
                     │   Graph Visualization   │
                     └─────────────────────────┘
```

---

## 🚀 Key Features

### 1. 100% Local & Zero Cloud Exposure
- Runs completely offline against your local Ollama daemon (`http://127.0.0.1:11434`).
- No OpenAI/Anthropic/Google API keys required.
- Confidential documents, source code, and PDFs never leave your machine.

### 2. Auto-Detection of Local Ollama Models
- Automatically queries `/api/tags` on application launch.
- Classifies models into:
  - **Chat / Completion Models**: `llama3.2`, `mistral`, `qwen2.5`, `deepseek-r1`, `phi3`, etc.
  - **Embedding Models**: `nomic-embed-text`, `bge-m3`, `all-minilm`, `mxbai-embed-large`, etc.
- Provides real-time server health checks and model download guidance.

### 3. True Hybrid Search Engine (BM25 + Dense Vectors + RRF)
- **BM25 Lexical Matching**: Implements Okapi BM25 with term frequency saturation ($k_1 = 1.5$) and document length normalization ($b = 0.75$).
- **Dense Vector Search**: Computes high-dimensional cosine similarity across vector embeddings generated by Ollama.
- **Reciprocal Rank Fusion (RRF)**: Merges sparse and dense ranking lists with configurable weighting ($w_{\text{dense}}$ vs $w_{\text{sparse}}$) and minimum score thresholds to filter noise.

### 4. Multi-PDF Ingestion & Smart Chunking
- Ingest multiple PDF documents simultaneously using `syncfusion_flutter_pdf`.
- Smart sliding-window chunker with token overlap to preserve cross-boundary semantics.
- Displays token metrics, chunk counts, document size, and chunk previews in the sidebar.

### 5. Interactive Knowledge Graph Suite (3 View Modes)
Transform any conversation or ingested document set into an interactive knowledge graph with three switchable visualization modes:

| Mode | Visual Style | Best Used For |
|---|---|---|
| **Neo4j Bloom / Constellation Mesh** | Multi-lobe constellation with hot-pink `#EC4899` concept nodes, periwinkle `#6366F1` chunk nodes, sky-blue `#38BDF8` document nodes, and straight relationship edges (`MENTIONS_CONCEPT`, `PART_OF`, `SIMILAR_TO`). | Exploring deep inter-chunk relationships, concept clusters, and ontology graphs. |
| **VISLABS Radial Starburst** | Radial hub-and-spoke starburst with central magenta `#D946EF` hub, mint `#2DD4BF` satellite nodes, numerical badges, relation spoke chips, selection bounding box, and radar mini-map. | Highlighting central focal points, primary topics, and direct associations. |
| **Dual-Track RAG Pipeline Flow** | Architectural flowchart with top user query, emerald Vector search track, cyan Knowledge Graph search track, and unified bottom Synthesis node. | System architecture audits, pipeline debugging, and workflow presentations. |

#### Physics & Canvas Engine:
- **Zero Idle CPU**: Automatic kinetic cool-down stabilizes simulation after 160 ticks, dropping CPU utilization to 0% when idle.
- **Interactive Controls**: Dynamic zoom, pan, node dragging with pin stabilization, and precise hit-testing scaled to any zoom factor (`18.0 / zoomScale`).
- **Right Inspector Panel**: Filter visible nodes by category (`chunk`, `concept`, `document`), filter edges by type (`MENTIONS_CONCEPT`, `PART_OF`, `SIMILAR_TO`), toggle straight edges, and inspect live record counts.

### 6. Multi-Format Export & Instant Caching
- **Deterministic 0ms Caching**: Graphs are cached in memory using deterministic MD5 hashing over conversation history and document chunks—switching views or re-opening is instantaneous.
- **Standalone Interactive HTML**: One-click download of a self-contained D3.js visualization with embedded physics, zoom, tooltips, and zero external dependencies (works completely offline).
- **Standard Knowledge Graph JSON**: Export machine-readable JSON containing nodes, edges, weights, categories, and badge metrics.
- **Mermaid.js Markdown (`.mmd`)**: Export ready-to-render Mermaid graph definitions for documentation and GitHub READMEs.

### 7. Modern Obsidian Glassmorphism UI
- Tailored dark obsidian color palette (`#090D16`, `#0C0A14`, `#13101F`, `#E8457C`, `#6366F1`, `#38BDF8`).
- Smooth animations, custom window header, markdown code-block styling with syntax highlighting, and responsive desktop layout.

---

## 🛠️ Architecture & Tech Stack

- **Framework**: Flutter Desktop (Windows target)
- **Language**: Dart (SDK `^3.13.5`)
- **Local Inference**: [Ollama REST API](https://github.com/ollama/ollama) (`/api/tags`, `/api/generate`, `/api/embeddings`)
- **PDF Engine**: `syncfusion_flutter_pdf`
- **Markdown Rendering**: `flutter_markdown`
- **File System**: `file_picker`
- **Search Math**: BM25 + Cosine Similarity + Reciprocal Rank Fusion (Native Dart implementation)
- **Physics Simulation**: Custom Velocity Verlet 2D Force-Directed Graph Layout Engine

---

## 📁 Directory Structure

```
local_hybrid_search_rag/
├── assets/
│   └── icons/                       # App icons and graphics
├── lib/
│   ├── main.dart                    # Application entry point & window setup
│   ├── models/
│   │   ├── chat_message.dart        # Message model with source citations & timestamps
│   │   ├── document_chunk.dart      # Chunk model with tokenization & embedding vectors
│   │   ├── knowledge_graph.dart     # Node, Edge, KnowledgeGraph models, D3/Mermaid/JSON export
│   │   └── ollama_model.dart        # Ollama model metadata and classification
│   ├── services/
│   │   ├── app_state.dart           # Central state management (ChangeNotifier)
│   │   ├── document_processor.dart  # PDF parsing, sliding-window chunking, token metrics
│   │   ├── hybrid_search_service.dart# BM25 lexical + Cosine dense vector + RRF search
│   │   ├── knowledge_graph_service.dart# Graph extraction, caching, and topology synthesis
│   │   └── ollama_service.dart      # HTTP client for Ollama API & fallback embeddings
│   └── ui/
│       ├── app_theme.dart           # Obsidian glassmorphism color palette & typography
│       ├── chat_view.dart           # Chat stream, toolbar, landing screen, prompt bar
│       ├── knowledge_graph_dialog.dart# Bloom/Starburst/Pipeline interactive canvas & inspector
│       └── sidebar.dart             # Model selector, PDF manager, chunk list, search settings
├── test/
│   ├── hybrid_search_test.dart      # Unit tests for BM25, cosine similarity, and RRF
│   ├── test_knowledge_graph.dart    # Unit tests for graph extraction, caching, and exporters
│   └── widget_test.dart             # Widget smoke test
├── pubspec.yaml                     # Dependencies and assets
└── README.md                        # Documentation
```

---

## 📋 Prerequisites

1. **Operating System**: Windows 10/11 (64-bit)
2. **Flutter SDK**: Version `3.13.5` or higher ([Installation Guide](https://docs.flutter.dev/get-started/install/windows))
3. **Visual Studio**: With "Desktop development with C++" workload installed (required for Flutter Windows desktop builds)
4. **Ollama**: Installed and running locally ([Download Ollama](https://ollama.com/download))

---

## ⚡ Installation & Quick Start

### 1. Clone the Repository
```powershell
git clone https://github.com/your-username/local_hybrid_search_rag.git
cd local_hybrid_search_rag
```

### 2. Install Dependencies
```powershell
flutter pub get
```

### 3. Start Ollama and Pull Recommended Models
Ensure Ollama is running in the background:
```powershell
# In PowerShell:
ollama serve
```

Pull an LLM model and an embedding model:
```powershell
# Chat Completion Model (Choose one):
ollama pull llama3.2
# or: ollama pull mistral
# or: ollama pull qwen2.5

# High-performance Embedding Model:
ollama pull nomic-embed-text
# or: ollama pull bge-m3
```

### 4. Run the Application
```powershell
flutter run -d windows
```

To build a release executable:
```powershell
flutter build windows --release
```
The compiled standalone Windows application will be located at:
`build/windows/x64/runner/Release/local_hybrid_search_rag.exe`

---

## 📖 User Guide

### Selecting Ollama Models
1. Launch the app. The left sidebar will automatically query `http://127.0.0.1:11434` for installed models.
2. Select your desired **Chat Model** (e.g., `llama3.2:latest`) from the dropdown.
3. Select your desired **Embedding Model** (e.g., `nomic-embed-text:latest`).
4. If Ollama is running on a custom port or remote LAN IP, you can modify the endpoint directly in the settings section.

### Loading Documents
1. In the sidebar, click **"Upload PDF"** or click **"Upload PDF Documents"** on the landing screen.
2. Select one or more `.pdf` files.
3. The app extracts text, segments it into overlapping chunks, generates embeddings using your selected embedding model, and indexes tokens for BM25 search.
4. Uploaded documents and total chunks are displayed in the sidebar.

### Chatting with Hybrid RAG
1. Type a question in the prompt input (e.g., *"What are the primary findings in the report?"*).
2. The search engine:
   - Queries the BM25 lexical index.
   - Calculates cosine similarity against vector embeddings.
   - Merges the scores using Reciprocal Rank Fusion.
   - Attaches the top-scoring chunks to the Ollama prompt.
3. The assistant streams the answer into the chat with citations showing chunk origin and confidence scores.

### Generating & Exploring the Knowledge Graph
1. Click the **"Knowledge Graph"** button in the top navigation bar, the landing page, or the message action toolbar.
2. The graph modal opens instantly using cached extracted topology:
   - **Bloom Mesh**: Inspect multi-cluster relationships between concepts, chunks, and parent documents.
   - **Radial Starburst**: Examine the central conversational hub and satellite entities with badges and mini-map.
   - **Pipeline Flow**: Visualize the dual-track Graph RAG vs Vector RAG flow down to synthesis.
3. **Canvas Controls**:
   - Left floating toolbar: Zoom In (`+`), Zoom Out (`-`), Reset / Fit to Screen, and Pause/Resume physics.
   - Drag nodes to reposition them; pinned nodes stay locked in place.
   - Right Inspector panel: Toggle visibility of node categories (`chunk`, `concept`, `document`) and edge types (`MENTIONS_CONCEPT`, `PART_OF`, `SIMILAR_TO`).

### Exporting Graph Artifacts
From the Knowledge Graph modal:
- Click **"Run query ▽"** or **"Download"** in the top bar / right inspector.
- Choose from:
  1. **Standalone HTML (`.html`)**: Self-contained interactive D3.js file with built-in physics, pan/zoom, and node inspectability.
  2. **Knowledge Graph JSON (`.json`)**: Raw nodes, links, and metadata for external graph databases or Python scripts.
  3. **Mermaid Markdown (`.mmd`)**: Ready to paste into GitHub, Obsidian, or Notion markdown files.

---

## 🧮 RAG Algorithm & Math

### 1. BM25 Lexical Ranking
Given a query $Q$ with terms $q_1, \dots, q_n$ and a document chunk $D$:
$$\text{BM25}(D, Q) = \sum_{i=1}^{n} \text{IDF}(q_i) \cdot \frac{f(q_i, D) \cdot (k_1 + 1)}{f(q_i, D) + k_1 \cdot \left(1 - b + b \cdot \frac{|D|}{\text{avgdl}}\right)}$$
- $k_1 = 1.5$ (term frequency saturation)
- $b = 0.75$ (document length normalization)
- $\text{avgdl}$ = average chunk token length across all indexed chunks

### 2. Dense Semantic Vector Search (Cosine Similarity)
Given query embedding vector $\vec{u}$ and chunk vector $\vec{v}$:
$$\text{Sim}_{\text{cosine}}(\vec{u}, \vec{v}) = \frac{\vec{u} \cdot \vec{v}}{\|\vec{u}\|_2 \, \|\vec{v}\|_2} = \frac{\sum_{i=1}^{d} u_i v_i}{\sqrt{\sum_{i=1}^{d} u_i^2} \sqrt{\sum_{i=1}^{d} v_i^2}}$$

### 3. Reciprocal Rank Fusion (RRF) & Weighted Hybrid Score
RRF normalizes disparate score distributions by ranking positions:
$$\text{Score}_{\text{RRF}}(D) = w_{\text{dense}} \cdot \frac{1}{k + \text{Rank}_{\text{dense}}(D)} + (1 - w_{\text{dense}}) \cdot \frac{1}{k + \text{Rank}_{\text{sparse}}(D)}$$
- $k = 60$ (smoothing constant preventing high-rank dominance)
- $w_{\text{dense}} = 0.5$ (default balanced weighting, configurable)

---

## 🧪 Testing & Quality Assurance

The codebase includes an automated test suite verifying search ranking, cosine similarity, graph extraction, caching, and export generation.

### Run All Unit & Integration Tests:
```powershell
flutter test test/test_knowledge_graph.dart test/hybrid_search_test.dart test/widget_test.dart
```

### Static Analysis:
```powershell
flutter analyze
```
*Current status: 0 errors, 0 warnings, 100% clean analysis.*

---

## 🔍 Troubleshooting

| Issue | Cause | Resolution |
|---|---|---|
| **"Cannot connect to Ollama"** | Ollama daemon is not running. | Run `ollama serve` in a terminal or start the Ollama desktop app. Ensure it listens on `http://127.0.0.1:11434`. |
| **"No models found"** | No models have been downloaded yet. | Run `ollama pull llama3.2` and `ollama pull nomic-embed-text` in PowerShell. |
| **PDF text extraction is empty** | Scanned image-only PDF without OCR text layer. | Ensure the PDF contains selectable digital text, or run an OCR pre-processor before importing. |
| **High CPU usage on graph canvas** | Physics simulation running indefinitely. | The physics simulation automatically enters sleep mode after 160 ticks. You can also click the Pause icon on the left floating toolbar. |
| **Missing Windows build tools** | Visual Studio C++ desktop workload not installed. | Run the Visual Studio Installer and check "Desktop development with C++". |

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
