import 'package:flutter/material.dart';

import '../services/chat_service.dart';

const _roleLabels = {
  'patient': 'You',
  'dispatcher': 'Dispatcher',
  'crew': 'Crew',
};

class ChatSheet extends StatefulWidget {
  const ChatSheet({super.key, required this.missionId, required this.title});

  final String missionId;
  final String title;

  static Future<void> open(
    BuildContext context, {
    required String missionId,
    required String title,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (_) =>
          ChatSheet(missionId: missionId, title: title),
    );
  }

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _chat = ChatService();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _chat.send(widget.missionId, text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(widget.title,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chat.watch(widget.missionId),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? const <ChatMessage>[];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet — say hello.'),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return Align(
                      alignment: m.fromMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.sizeOf(context).width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: m.fromMe
                              ? Colors.indigo.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _roleLabels[m.senderRole] ?? m.senderRole,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: Colors.indigo),
                            ),
                            Text(m.text),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration:
                        const InputDecoration(hintText: 'Type a message…'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
