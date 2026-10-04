import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.senderRole,
    required this.at,
  });

  final String id;
  final String text;
  final String senderRole;
  final DateTime at;

  bool get fromMe => senderRole == 'patient';
}

class ChatService {
  CollectionReference<Map<String, dynamic>> _thread(String missionId) =>
      FirebaseFirestore.instance
          .collection('missions')
          .doc(missionId)
          .collection('messages');

  Stream<List<ChatMessage>> watch(String missionId) {
    return _thread(missionId)
        .orderBy('at', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) {
            final data = d.data();
            final ts = data['at'];
            return ChatMessage(
              id: d.id,
              text: (data['text'] as String?) ?? '',
              senderRole: (data['senderRole'] as String?) ?? 'unknown',
              at: ts is Timestamp ? ts.toDate() : DateTime.now(),
            );
          }).toList(),
        );
  }

  Future<void> send(String missionId, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    return _thread(missionId).add({
      'text': trimmed,
      'senderRole': 'patient',
      'senderId': FirebaseAuth.instance.currentUser?.uid,
      'at': FieldValue.serverTimestamp(),
    });
  }
}
