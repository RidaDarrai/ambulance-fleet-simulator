import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../widgets/atoms.dart';

/// Mission chat (spec §10) — dispatcher + patient, right/left bubbles,
/// offline shows queued [pending] dots on the last crew message.
class ChatScreen extends StatefulWidget {
  final AppState state;
  final String missionId;
  const ChatScreen({super.key, required this.state, required this.missionId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.openChat(widget.missionId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  void _toEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _send([String? quick]) {
    final text = quick ?? _controller.text;
    state.sendMessage(widget.missionId, text, quick: quick != null);
    if (quick == null) _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static const _quickPhrases = [
    'Running 5 minutes late',
    'Approaching the pickup point',
    'Patient is on board',
    'Need traffic support',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = state.mission(widget.missionId) ?? state.activeMission;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final messages = state.messages(widget.missionId);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m?.status.stripLabel ?? 'Mission chat',
                    style: theme.textTheme.titleMedium),
                if (m != null)
                  Text('${state.ambulanceId} · dispatcher + patient',
                      style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          body: Column(
            children: [
              if (state.offline) ...[
                const OfflineBanner(),
                gapH(4),
              ],
              Expanded(
                child: messages.isEmpty
                    ? EmptyStateBox(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'No messages yet',
                        message: 'Coordinate with dispatch and the patient '
                            'during this mission.',
                        actionLabel: 'Send "Approaching the pickup point"',
                        onAction: () =>
                            _send('Approaching the pickup point'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, i) => _Bubble(
                          message: messages[i],
                          theme: theme,
                        ),
                      ),
              ),
              // Quick phrases (§9).
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _quickPhrases.length,
                  separatorBuilder: (_, _) => gapW(8),
                  itemBuilder: (context, i) => ActionChip(
                    label: Text(_quickPhrases[i]),
                    onPressed: () => _send(_quickPhrases[i]),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              gapH(8),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Message dispatch…',
                          ),
                        ),
                      ),
                      gapW(10),
                      IconButton.filled(
                        onPressed: () => _send(),
                        icon: const Icon(Icons.send_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final ThemeData theme;
  const _Bubble({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    final crew = message.senderRole == 'crew';
    final patient = message.senderRole == 'patient';
    return Align(
      alignment: crew ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: crew
              ? theme.colorScheme.primary
              : patient
                  ? AppColors.statusOnScene.withValues(alpha: 0.16)
                  : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppColors.radiusMd),
            topRight: const Radius.circular(AppColors.radiusMd),
            bottomLeft: Radius.circular(crew ? AppColors.radiusMd : 2),
            bottomRight: Radius.circular(crew ? 2 : AppColors.radiusMd),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: crew ? Colors.white : null,
              ),
            ),
            gapH(3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!crew && patient)
                  Text('Patient · ',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontSize: 10)),
                Text(
                  '${message.at.hour.toString().padLeft(2, '0')}:'
                  '${message.at.minute.toString().padLeft(2, '0')}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: crew ? Colors.white70 : null,
                  ),
                ),
                if (message.pending) ...[
                  gapW(4),
                  Icon(Icons.schedule_rounded,
                      size: 11,
                      color: crew
                          ? Colors.white70
                          : context.statusColor(MissionStatus.assigned)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
