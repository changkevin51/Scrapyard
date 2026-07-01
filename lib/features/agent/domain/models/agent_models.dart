enum AgentCommand { restructure, studyPlan, webSearch, summarise, ask }

class RestructureResult {
  final String original;
  final String proposed;
  const RestructureResult({required this.original, required this.proposed});
}

class StudyTopic {
  final String name;
  final String description;
  final List<String> resources;
  const StudyTopic({required this.name, required this.description, required this.resources});
}

class StudyPlan {
  final String title;
  final int estimatedHours;
  final List<StudyTopic> topics;
  const StudyPlan({required this.title, required this.estimatedHours, required this.topics});
}

class ConversationMessage {
  final String text;
  final bool isUser;
  const ConversationMessage({required this.text, required this.isUser});
}
