import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';
import '../models/document_chunk.dart';
import '../services/app_state.dart';
import 'app_theme.dart';
import 'knowledge_graph_dialog.dart';

class ChatView extends StatefulWidget {
  final AppState state;

  const ChatView({super.key, required this.state});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleSend([String? presetText]) {
    final text = (presetText ?? _inputController.text).trim();
    if (text.isEmpty || widget.state.isGenerating) return;

    _inputController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputController.text.isNotEmpty) {
        _inputController.clear();
      }
    });

    widget.state.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          // Sleek Header Bar
          _buildTopBar(state),

          const Divider(height: 1, color: AppTheme.border),

          // Message List or Empty State
          Expanded(
            child: state.chatHistory.isEmpty
                ? _buildEmptyState(state)
                : _buildMessageList(state),
          ),

          // Floating Input Composer
          _buildFloatingInputBar(state),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Sidebar Toggle
            if (!state.isSidebarOpen) ...[
              IconButton(
                tooltip: 'Open Sidebar',
                icon: const Icon(Icons.menu_rounded, size: 20, color: AppTheme.textPrimary),
                onPressed: () => state.toggleSidebar(),
              ),
              const SizedBox(width: 8),
            ],

            // Active Model Chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.memory_rounded, size: 14, color: AppTheme.primaryLight),
                  const SizedBox(width: 6),
                  Text(
                    state.selectedModel ?? 'No Model',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // RAG Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: state.hasDocuments
                    ? AppTheme.accentGreen.withValues(alpha: 0.12)
                    : AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: state.hasDocuments
                      ? AppTheme.accentGreen.withValues(alpha: 0.35)
                      : AppTheme.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.hasDocuments ? AppTheme.accentGreen : AppTheme.textMuted,
                      boxShadow: state.hasDocuments
                          ? [
                              BoxShadow(
                                color: AppTheme.accentGreen.withValues(alpha: 0.5),
                                blurRadius: 6,
                              )
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state.hasDocuments
                        ? 'Hybrid Index Ready (${state.totalIndexedChunks} chunks)'
                        : 'General LLM Mode',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: state.hasDocuments ? AppTheme.accentGreen : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Generate / View Knowledge Graph Button (Always accessible)
            FilledButton.icon(
              icon: const Icon(Icons.hub_rounded, size: 14),
              label: const Text('Knowledge Graph', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
              ),
              onPressed: () => KnowledgeGraphDialog.show(context, state),
            ),
            const SizedBox(width: 8),

            // Clear Chat
            if (state.chatHistory.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.cleaning_services_rounded, size: 13),
                label: const Text('Clear Chat', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: () => state.clearChat(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppState state) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppTheme.primary,
                      child: const Icon(Icons.hub_rounded, size: 36, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'High-Speed Local Hybrid RAG',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Query your local PDFs and documents with zero cloud latency. Powered by BM25 sparse lexical search + Ollama dense vector similarity with Reciprocal Rank Fusion.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 28),

              if (!state.hasDocuments)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file_rounded, size: 17),
                      label: const Text('Upload PDF Documents'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => state.pickAndProcessFiles(),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.hub_rounded, size: 17, color: Color(0xFFE8457C)),
                      label: const Text('Explore Knowledge Graph'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => KnowledgeGraphDialog.show(context, state),
                    ),
                  ],
                )
              else ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.hub_rounded, size: 16, color: Color(0xFFE8457C)),
                  label: const Text('Explore Knowledge Graph'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => KnowledgeGraphDialog.show(context, state),
                ),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Suggested Quick Prompts',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPromptCard(
                          icon: Icons.auto_stories_rounded,
                          title: 'Summarize Key Insights',
                          subtitle: 'Generate a comprehensive summary of all documents',
                          onTap: () => _handleSend('Please provide a complete and structured summary of the loaded documents.'),
                        ),
                        _buildPromptCard(
                          icon: Icons.find_in_page_rounded,
                          title: 'Technical Concepts',
                          subtitle: 'Extract all core definitions and parameters',
                          onTap: () => _handleSend('What are the key technical concepts, architectures, and formulas mentioned?'),
                        ),
                        _buildPromptCard(
                          icon: Icons.checklist_rounded,
                          title: 'Action Items & Takeaways',
                          subtitle: 'List concrete next steps and conclusions',
                          onTap: () => _handleSend('List the key takeaways, action items, and conclusions from the text.'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: AppTheme.primaryLight),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(AppState state) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      itemCount: state.chatHistory.length,
      itemBuilder: (context, index) {
        final message = state.chatHistory[index];
        return _buildMessageItem(message, state);
      },
    );
  }

  Widget _buildMessageItem(ChatMessage message, AppState state) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: AppTheme.primary,
                    child: const Icon(Icons.hub_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.primary : AppTheme.cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 3),
                  bottomRight: Radius.circular(isUser ? 3 : 16),
                ),
                border: Border.all(
                  color: isUser ? AppTheme.primaryLight.withValues(alpha: 0.4) : AppTheme.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header stats for Assistant response
                  if (!isUser) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          state.selectedModel ?? 'Ollama',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                        ),
                        if (message.retrievalDurationMs != null)
                          Text(
                            '⚡ ${message.retrievalDurationMs}ms search'
                            '${message.tokensPerSecond != null ? ' • ${(message.tokensPerSecond!).toStringAsFixed(0)} tok/s' : ''}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Content
                  if (isUser)
                    SelectableText(
                      message.content,
                      style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.45),
                    )
                  else ...[
                    MarkdownBody(
                      data: message.content.isEmpty && message.isStreaming
                          ? 'Generating response...'
                          : message.content + (message.isStreaming ? ' ▌' : ''),
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.55),
                        code: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Consolas',
                          backgroundColor: Color(0xFF090D16),
                          color: AppTheme.secondary,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: const Color(0xFF090D16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                      ),
                    ),

                    if (message.isFallback) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 12, color: AppTheme.accentOrange),
                            SizedBox(width: 6),
                            Text(
                              'Answered from general knowledge (no direct match in indexed documents)',
                              style: TextStyle(fontSize: 11, color: AppTheme.accentOrange),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Retrieved Context Sources Accordion
                    if (message.sources.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSourcesAccordion(message.sources),
                    ],

                    // Action Toolbar
                    if (!message.isStreaming && message.content.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.hub_outlined, size: 14, color: AppTheme.textMuted),
                            tooltip: 'Explore Knowledge Graph',
                            splashRadius: 14,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => KnowledgeGraphDialog.show(context, state),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 14, color: AppTheme.textMuted),
                            tooltip: 'Copy response',
                            splashRadius: 14,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: message.content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied response to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryLight),
              ),
              child: const Icon(Icons.person_rounded, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourcesAccordion(List<SearchResult> sources) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: AppTheme.textSecondary,
        collapsedIconColor: AppTheme.textMuted,
        dense: true,
        leading: const Icon(Icons.auto_stories_rounded, size: 16, color: AppTheme.secondary),
        title: Text(
          'Retrieved Context (${sources.length} sources used)',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondary),
        ),
        children: sources.map((s) {
          final matchPercent = (s.denseScore * 100).toInt().clamp(1, 100);
          return Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '📄 ${s.chunk.docName} • Page ${s.chunk.pageNumber}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$matchPercent% Match • BM25: ${s.sparseScore.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.secondary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  s.chunk.text,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.45),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFloatingInputBar(AppState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      color: AppTheme.background,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: KeyboardListener(
                focusNode: _focusNode,
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _handleSend();
                  }
                },
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    hintText: state.hasDocuments
                        ? 'Ask a question about the loaded documents (Enter to send, Shift+Enter for newline)...'
                        : 'Ask anything with your local Ollama model...',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (state.isGenerating)
              ElevatedButton.icon(
                icon: const Icon(Icons.stop_rounded, size: 16),
                label: const Text('Stop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentRed,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => state.stopGeneration(),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
                  onPressed: () => _handleSend(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
