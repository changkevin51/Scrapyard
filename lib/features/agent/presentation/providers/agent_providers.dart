import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/agent_models.dart';
import '../../data/token_repository.dart';
import '../../data/agent_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());
final tokenRepositoryProvider = Provider((ref) => TokenRepository());

final agentServiceProvider = Provider((ref) {
  return AgentService(ref.watch(secureStorageProvider), ref.watch(tokenRepositoryProvider));
});

final activeAgentCommandProvider = StateProvider<AgentCommand>((ref) => AgentCommand.ask);
final agentConversationProvider = StateProvider<List<ConversationMessage>>((ref) => []);
final showAgentPanelProvider = StateProvider<bool>((ref) => false);
final dailyTokensProvider = FutureProvider<int>((ref) {
  return ref.watch(tokenRepositoryProvider).getDailyTokens();
});
