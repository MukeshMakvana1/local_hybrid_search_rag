import 'package:flutter/material.dart';
import 'services/app_state.dart';
import 'ui/app_theme.dart';
import 'ui/chat_view.dart';
import 'ui/sidebar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HybridRagDesktopApp());
}

class HybridRagDesktopApp extends StatelessWidget {
  const HybridRagDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Hybrid Search RAG Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = AppState();
    _appState.init();
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _appState,
        builder: (context, _) {
          return Row(
            children: [
              // Left Sidebar
              AppSidebar(state: _appState),

              // Main Chat Area
              Expanded(
                child: ChatView(state: _appState),
              ),
            ],
          );
        },
      ),
    );
  }
}
