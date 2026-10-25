import 'package:flutter_test/flutter_test.dart';
import 'package:local_hybrid_search_rag/main.dart';

void main() {
  testWidgets('HybridRagDesktopApp smoke test', (WidgetTester tester) async {
    // Build our desktop app and trigger a frame.
    await tester.pumpWidget(const HybridRagDesktopApp());

    // Verify key UI components render
    expect(find.text('Hybrid RAG'), findsOneWidget);
    expect(find.text('Local Ollama Desktop'), findsOneWidget);
    expect(find.text('ACTIVE MODEL'), findsOneWidget);
    expect(find.text('VECTOR EMBEDDER'), findsOneWidget);
    expect(find.text('KNOWLEDGE BASE'), findsOneWidget);
  });
}
