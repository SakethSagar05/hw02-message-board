import 'package:flutter/material.dart';

import '../config.dart';
import '../models/app_user.dart';
import '../models/message.dart';
import '../services/app_exception.dart';
import '../services/auth_service.dart';
import '../services/board_service.dart';
import '../services/validators.dart';
import 'rules_lab_screen.dart';

/// The message board: live stream (Read), composer (Create), and
/// edit/delete on the signed-in user's own messages (Update/Delete).
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.me, required this.auth});
  final AppUser me;
  final AuthService auth;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final BoardService _board = BoardService();

  /// Created once; StreamBuilder cancels it when this screen is disposed,
  /// so navigating never leaves an extra listener running.
  late Stream<BoardWindow> _window = _board.liveWindow();

  final _composer = TextEditingController();
  late String _draftId = _board.newMessageId();
  bool _posting = false;

  // Older history pages (one-shot reads, Spice #6).
  final List<Message> _older = [];
  PageCursor? _nextOlder;
  bool _olderStarted = false;
  bool _loadingOlder = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _post() async {
    if (_posting) return; // double-tap guard; the id makes retries safe too
    final problem = Validators.message(_composer.text);
    if (problem != null) {
      _snack(problem);
      return;
    }
    setState(() => _posting = true);
    try {
      final result = await _board.postMessage(
        messageId: _draftId,
        authorUid: widget.me.uid,
        authorName: widget.me.displayName,
        text: _composer.text,
      );
      _composer.clear();
      _draftId = _board.newMessageId(); // next draft, next id
      if (result == PostResult.alreadyPosted) {
        _snack('Already posted. No duplicate was created.');
      }
    } on AppException catch (e) {
      // Keep the text and the same draft id, so a retry cannot duplicate.
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _edit(Message m) async {
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => _EditDialog(initial: m.text),
    );
    if (newText == null || newText.trim() == m.text) return;
    try {
      await _board.editMessage(messageId: m.id, newText: newText);
      _patchOlder(m.id, (old) => old.copyWith(text: newText.trim(), editedAt: DateTime.now()));
      _snack('Message updated.');
    } on AppException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this message?'),
        content: Text('"${_preview(m.text)}" will be removed for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _board.deleteMessage(messageId: m.id);
      setState(() => _older.removeWhere((o) => o.id == m.id));
      _snack('Message deleted.');
    } on AppException catch (e) {
      _snack(e.message);
    }
  }

  void _patchOlder(String id, Message Function(Message) change) {
    final i = _older.indexWhere((o) => o.id == id);
    if (i >= 0) setState(() => _older[i] = change(_older[i]));
  }

  Future<void> _loadOlder(PageCursor? windowCursor) async {
    final cursor = _olderStarted ? _nextOlder : windowCursor;
    if (cursor == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _board.loadOlder(cursor);
      setState(() {
        _olderStarted = true;
        _older.addAll(page.messages);
        _nextOlder = page.next;
      });
    } on AppException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// Called after the Rules Lab seeds or clears messages: start the live
  /// window again so its anchor reflects the new board.
  void _restartBoard() {
    setState(() {
      _older.clear();
      _nextOlder = null;
      _olderStarted = false;
      _window = _board.liveWindow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          IconButton(
            tooltip: 'Rules Lab',
            icon: const Icon(Icons.science_outlined),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => RulesLabScreen(me: widget.me)),
              );
              // The lab may have seeded or cleared messages: re-anchor the
              // live window so pagination starts from the current board.
              if (mounted) _restartBoard();
            },
          ),
          TextButton(onPressed: widget.auth.signOut, child: const Text('Sign out')),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Signed in as ${widget.me.displayName} · ${widget.me.role}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: StreamBuilder<BoardWindow>(
              stream: _window,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final e = snapshot.error;
                  return _CenteredState(
                    icon: Icons.cloud_off,
                    title: 'Could not load the board',
                    detail: e is AppException ? e.message : 'Try again.',
                    action: FilledButton(onPressed: _restartBoard, child: const Text('Retry')),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final window = snapshot.data!;
                final liveIds = window.messages.map((m) => m.id).toSet();
                final messages = [
                  ...window.messages,
                  ..._older.where((m) => !liveIds.contains(m.id)),
                ];
                final hasMore =
                    _olderStarted ? _nextOlder != null : window.olderCursor != null;
                if (messages.isEmpty && !hasMore) {
                  return const _CenteredState(
                    icon: Icons.forum_outlined,
                    title: 'No messages yet',
                    detail: 'The board is empty. Be the first to post.',
                  );
                }
                return ListView.builder(
                  reverse: true, // newest at the bottom, like a chat
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == messages.length) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: _loadingOlder
                              ? const CircularProgressIndicator()
                              : OutlinedButton(
                                  onPressed: () => _loadOlder(window.olderCursor),
                                  child: const Text('Load older messages'),
                                ),
                        ),
                      );
                    }
                    final m = messages[i];
                    return _MessageTile(
                      message: m,
                      mine: m.isOwnedBy(widget.me.uid),
                      onEdit: () => _edit(m),
                      onDelete: () => _delete(m),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      enabled: !_posting,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: Validators.maxMessageLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Write a message',
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _posting ? null : _post,
                    child: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Post'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _preview(String text) => text.length <= 40 ? text : '${text.substring(0, 40)}…';

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTime(DateTime t) {
  final local = t.toLocal();
  final now = DateTime.now();
  final hm = '${_two(local.hour)}:${_two(local.minute)}';
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  return sameDay ? hm : '${local.month}/${local.day}/${local.year} $hm';
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.mine,
    required this.onEdit,
    required this.onDelete,
  });

  final Message message;
  final bool mine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = message;
    final meta = m.isPending
        ? 'Sending…'
        : '${_formatTime(m.createdAt!)}${m.isEdited ? ' · edited' : ''}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Card(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mine ? '${m.authorName} (you)' : m.authorName,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(m.text),
                      const SizedBox(height: 4),
                      Text(meta, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                // Edit/delete appear only on your own messages. This is UX;
                // the security rules are what actually stop other users.
                if (mine)
                  PopupMenuButton<String>(
                    tooltip: 'Message options',
                    onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.initial});
  final String initial;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit message'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: Validators.maxMessageLength,
          decoration: const InputDecoration(labelText: 'Message text'),
          validator: Validators.message,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.pop(context, _text.text);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(detail, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
