import 'package:flutter/material.dart';
import '../models/ollama_model.dart';
import '../services/app_state.dart';
import 'app_theme.dart';

class AppSidebar extends StatefulWidget {
  final AppState state;

  const AppSidebar({super.key, required this.state});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _showSettings = false;
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.state.baseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: state.isSidebarOpen ? 340 : 0,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          right: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: state.isSidebarOpen
          ? Column(
              children: [
                _buildHeader(state),
                const Divider(height: 1, color: AppTheme.border),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    children: [
                      _buildModelSelector(state),
                      const SizedBox(height: 16),
                      _buildDocumentSection(state),
                      const SizedBox(height: 16),
                      _buildAdvancedSettings(state),
                    ],
                  ),
                ),
                _buildFooter(state),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildHeader(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppTheme.primary,
                  child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hybrid RAG',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Local Ollama Desktop',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Rescan Ollama Models',
            icon: state.isLoadingModels
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                  )
                : const Icon(Icons.refresh_rounded, size: 19, color: AppTheme.textSecondary),
            onPressed: state.isLoadingModels ? null : () => state.refreshModels(),
          ),
          IconButton(
            tooltip: 'Collapse Sidebar',
            icon: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 19, color: AppTheme.textSecondary),
            onPressed: () => state.toggleSidebar(),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(AppState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection Status Pill
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.isOllamaConnected ? AppTheme.accentGreen : AppTheme.accentRed,
                  boxShadow: [
                    BoxShadow(
                      color: (state.isOllamaConnected ? AppTheme.accentGreen : AppTheme.accentRed)
                          .withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.isOllamaConnected
                      ? 'Ollama Active • ${state.models.length} Models'
                      : 'Ollama Disconnected',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: state.isOllamaConnected ? AppTheme.accentGreen : AppTheme.accentRed,
                  ),
                ),
              ),
              if (state.selectedModel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Text('120 FPS', style: TextStyle(fontSize: 10, color: AppTheme.primaryLight, fontWeight: FontWeight.bold)),
                ),
            ],
          ),

          if (state.connectionError != null) ...[
            const SizedBox(height: 8),
            Text(
              state.connectionError!,
              style: const TextStyle(fontSize: 11, color: AppTheme.accentRed),
            ),
          ],

          const SizedBox(height: 14),

          // Active Generative Model
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ACTIVE MODEL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              if (state.models.any((m) => m.speedBadge.contains('Instant')))
                const Text('⚡ Instant Available', style: TextStyle(fontSize: 10, color: AppTheme.secondary)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: Builder(
                builder: (context) {
                  final uniqueModels = <String, OllamaModel>{};
                  for (final m in state.models) {
                    uniqueModels[m.name] = m;
                  }
                  final safeValue = uniqueModels.containsKey(state.selectedModel) ? state.selectedModel : null;

                  return DropdownButton<String>(
                    isExpanded: true,
                    value: safeValue,
                    hint: const Text('Select Ollama model', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                    dropdownColor: AppTheme.surfaceLight,
                    items: uniqueModels.values.map((OllamaModel m) {
                      return DropdownMenuItem<String>(
                        value: m.name,
                        child: Text(
                          m.displayName,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => state.setSelectedModel(val),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Embedding Model
          const Text(
            'VECTOR EMBEDDER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: Builder(
                builder: (context) {
                  final uniqueModels = <String, OllamaModel>{};
                  for (final m in state.models) {
                    uniqueModels[m.name] = m;
                  }
                  final safeEmbedValue = uniqueModels.containsKey(state.embeddingModel) ? state.embeddingModel : null;

                  return DropdownButton<String>(
                    isExpanded: true,
                    value: safeEmbedValue,
                    hint: const Text('Auto-detected embedder', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                    dropdownColor: AppTheme.surfaceLight,
                    items: uniqueModels.values.map((OllamaModel m) {
                      final isDed = m.isEmbeddingModel;
                      return DropdownMenuItem<String>(
                        value: m.name,
                        child: Text(
                          '${isDed ? '🎯 ' : ''}${m.name}${isDed ? ' (Dedicated Batch)' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDed ? AppTheme.secondary : AppTheme.textPrimary,
                            fontWeight: isDed ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => state.setEmbeddingModel(val),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentSection(AppState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'KNOWLEDGE BASE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              if (state.documents.isNotEmpty)
                InkWell(
                  onTap: () => state.clearAllDocuments(),
                  child: const Text(
                    'Clear All',
                    style: TextStyle(fontSize: 11, color: AppTheme.accentRed, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${state.documents.length} document(s) • ${state.totalIndexedChunks} chunks indexed',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),

          const SizedBox(height: 12),

          // Upload Button with Gradient
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: state.isProcessingDocs
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: Text(state.isProcessingDocs ? 'Batch Indexing...' : 'Upload PDF / Text Docs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: state.isProcessingDocs ? null : () => state.pickAndProcessFiles(),
            ),
          ),

          if (state.isProcessingDocs) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: state.docProcessingProgress,
                backgroundColor: AppTheme.surfaceLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.secondary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              state.docProcessingStatus,
              style: const TextStyle(fontSize: 11, color: AppTheme.secondary, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (state.docProcessingStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.docProcessingStatus,
              style: const TextStyle(fontSize: 11, color: AppTheme.accentGreen, fontWeight: FontWeight.w500),
            ),
          ],

          if (state.documents.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: state.documents.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final doc = state.documents[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.description_rounded, size: 16, color: AppTheme.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                doc.fileName,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${doc.pageCount} page(s) • ${doc.chunkCount} chunks',
                                style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppTheme.textMuted),
                          splashRadius: 14,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => state.removeDocument(doc.fileName),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdvancedSettings(AppState state) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            ListTile(
              dense: true,
              title: const Text(
                'Hybrid Search Parameters',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              trailing: Icon(
                _showSettings ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onTap: () {
                setState(() {
                  _showSettings = !_showSettings;
                });
              },
            ),
            if (_showSettings)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1, color: AppTheme.border),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Search Fusion', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        Text(
                          state.denseWeight == 0.0
                              ? 'Pure BM25'
                              : state.denseWeight == 1.0
                                  ? 'Pure Vector'
                                  : 'Hybrid (${(state.denseWeight * 100).toInt()}% Dense)',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                        ),
                      ],
                    ),
                    Slider(
                      value: state.denseWeight,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      onChanged: (v) => state.setDenseWeight(v),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Top-K Chunks', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        Text('${state.topK}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight)),
                      ],
                    ),
                    Slider(
                      value: state.topK.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      onChanged: (v) => state.setTopK(v.round()),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Temperature', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        Text(state.temperature.toStringAsFixed(2), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight)),
                      ],
                    ),
                    Slider(
                      value: state.temperature,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (v) => state.setTemperature(v),
                    ),

                    const SizedBox(height: 6),
                    const Text('Ollama Server URL', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            style: const TextStyle(fontSize: 11),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onPressed: () => state.updateBaseUrl(_urlController.text),
                          child: const Text('Apply', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed_rounded, size: 15, color: AppTheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.selectedModel != null ? 'Active: ${state.selectedModel}' : 'No model selected',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
