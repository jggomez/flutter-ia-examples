import 'chat_role.dart';
import 'citation.dart';

/// Represents a user or assistant message in a StudyGemma session.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.citations = const [],
    this.isStreaming = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final List<Citation> citations;
  final bool isStreaming;

  String get content => text;

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? text,
    DateTime? createdAt,
    List<Citation>? citations,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      citations: citations ?? this.citations,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatMessage) return false;
    if (other.id != id ||
        other.role != role ||
        other.text != text ||
        other.createdAt != createdAt ||
        other.isStreaming != isStreaming ||
        other.citations.length != citations.length) {
      return false;
    }
    for (var i = 0; i < citations.length; i++) {
      if (other.citations[i] != citations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    role,
    text,
    createdAt,
    Object.hashAll(citations),
    isStreaming,
  );
}
