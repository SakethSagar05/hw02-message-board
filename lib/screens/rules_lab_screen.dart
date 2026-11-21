import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/app_exception.dart';
import '../services/board_service.dart';
import '../services/rules_probe_service.dart';

/// One row of evidence: action, expected, observed, pass/fail.
class _Check {
  _Check({required this.id, required this.action, required this.expected});

  final String id;
  final String action;
  final String expected;
  String? observed;
  bool? passed; // null = not run or skipped
  bool running = false;
}

String _describe(ProbeOutcome o) => o.allowed
    ? 'ALLOWED (the database accepted it)'
    : 'DENIED by Firestore: ${o.code}';

bool _deniedByRules(ProbeOutcome o) => !o.allowed && o.code == 'permission-denied';

/// Signed-in Rules Lab: tries what the UI never offers, straight against the
/// database, and records what Firestore answered.
class RulesLabScreen extends StatefulWidget {
  const RulesLabScreen({super.key, required this.me});
  final AppUser me;

  @override
  State<RulesLabScreen> createState() => _RulesLabScreenState();
}

class _RulesLabScreenState extends State<RulesLabScreen> {
  final BoardService _board = BoardService();
  late final RulesProbeService _probe = RulesProbeService(board: _board);

  final List<_Check> _checks = [
    _Check(
        id: 'edit',
        action: "Edit another user's message (UI bypassed)",
        expected: 'Denied: permission-denied'),
    _Check(
        id: 'delete',
        action: "Delete another user's message (UI bypassed)",
        expected: 'Denied: permission-denied'),
    _Check(
        id: 'forged',
        action: 'Create a message with a forged authorUid',
        expected: 'Denied: permission-denied'),
    _Check(
        id: 'owner',
        action: 'Change the authorUid of my own message',
        expected: 'Denied: permission-denied'),
    _Check(
        id: 'clock',
        action: 'Create with a device-clock createdAt (2001-01-01)',
        expected: 'Denied: permission-denied'),
    _Check(
        id: 'record',
        action: "Read another user's private users/{uid} record",
        expected: 'Denied: permission-denied'),
  ];

  String? _dupResult;
  bool? _dupPassed;
  bool _dupRunning = false;

  String? _bulkStatus;
  bool _bulkRunning = false;

  Future<void> _run(_Check c) async {
    setState(() {
      c.running = true;
      c.observed = null;
      c.passed = null;
    });
    final uid = widget.me.uid;
    try {
      ProbeOutcome? outcome;
      String? skip;
      switch (c.id) {
        case 'edit':
        case 'delete':
        case 'record':
          final other = await _probe.findOtherAuthorsMessage(uid);
          if (other == null) {
            skip = 'SKIPPED: no message by another user yet. Sign in as a second '
                'user, post one, then come back as this user.';
          } else if (c.id == 'edit') {
            outcome = await _probe.crossUserEdit(other.id);
          } else if (c.id == 'delete') {
            outcome = await _probe.crossUserDelete(other.id);
          } else {
            outcome = await _probe.readOtherUserRecord(other.authorUid);
          }
          if (other != null) {
            c.observed = 'Target: "${other.text}" by ${other.authorName}. ';
          }
        case 'forged':
          outcome = await _probe.forgedAuthorCreate();
        case 'owner':
          final mine = await _probe.findMyMessage(uid);
          if (mine == null) {
            skip = 'SKIPPED: post one message of your own first.';
          } else {
            c.observed = 'Target: my message "${mine.text}". ';
            outcome = await _probe.changeOwner(mine.id);
          }
        case 'clock':
          outcome = await _probe.deviceClockCreate(uid, widget.me.displayName);
      }
      final String observed;
      final bool? passed;
      if (skip != null || outcome == null) {
        observed = skip ?? 'SKIPPED';
        passed = null;
      } else {
        observed = '${c.observed ?? ''}${_describe(outcome)}';
        passed = _deniedByRules(outcome);
      }
      setState(() {
        c.observed = observed;
        c.passed = passed;
      });
    } catch (e) {
      setState(() {
        c.observed = 'Error: ${e is AppException ? e.message : e}';
        c.passed = false;
      });
    } finally {
      if (mounted) setState(() => c.running = false);
    }
  }

  Future<void> _runAll() async {
    for (final c in _checks) {
      await _run(c);
    }
  }

  Future<void> _doubleSubmit() async {
    setState(() {
      _dupRunning = true;
      _dupResult = null;
      _dupPassed = null;
    });
    try {
      final r = await _probe.doubleSubmit(
          uid: widget.me.uid, name: widget.me.displayName);
      final names = r.results.map((x) => x.name).join(', ');
      setState(() {
        _dupPassed = r.documents == 1 &&
            r.results.where((x) => x == PostResult.created).length == 1;
        _dupResult = 'Three calls with one draft id returned [$names]. '
            'Documents in Firestore with that text: ${r.documents}.';
      });
    } catch (e) {
      setState(() {
        _dupPassed = false;
        _dupResult = 'Error: ${e is AppException ? e.message : e}';
      });
    } finally {
      if (mounted) setState(() => _dupRunning = false);
    }
  }

  Future<void> _seed() async {
    setState(() {
      _bulkRunning = true;
      _bulkStatus = 'Seeding…';
    });
    try {
      await _board.seedMessages(
        authorUid: widget.me.uid,
        authorName: widget.me.displayName,
        onProgress: (n) {
          if (mounted && (n % 5 == 0)) setState(() => _bulkStatus = 'Seeded $n of 120…');
        },
      );
      setState(() => _bulkStatus =
          'Seeded 120 messages. Go back to the board and use "Load older messages".');
    } on AppException catch (e) {
      setState(() => _bulkStatus = 'Seeding stopped: ${e.message}');
    } finally {
      if (mounted) setState(() => _bulkRunning = false);
    }
  }

  Future<void> _clearMine() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all of your messages?'),
        content: const Text('One atomic batched write removes every message you wrote.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete all')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _bulkRunning = true;
      _bulkStatus = 'Deleting in one batch…';
    });
    try {
      final n = await _board.deleteAllMine(widget.me.uid);
      setState(() => _bulkStatus = 'Batch committed: deleted $n of your messages. '
          "Other users' messages were not touched.");
    } on AppException catch (e) {
      setState(() => _bulkStatus = 'Batch failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _bulkRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Rules Lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Signed in as ${widget.me.displayName}. These calls skip the UI and go '
            'straight to Firestore, so any denial below comes from the security '
            'rules, not from hidden buttons.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run all denial checks'),
            onPressed: _checks.any((c) => c.running) ? null : _runAll,
          ),
          const SizedBox(height: 8),
          for (final c in _checks) _CheckCard(check: c, onRun: () => _run(c)),
          const SizedBox(height: 16),
          Text('Duplicate submit (Extra Spice #4)', style: text.titleMedium),
          const SizedBox(height: 4),
          const Text('Posts the same draft twice at once, then once more as a retry. '
              'Expected: one "created", the rest "alreadyPosted", exactly 1 document.'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _dupRunning ? null : _doubleSubmit,
            child: const Text('Run double-submit test'),
          ),
          if (_dupRunning) const LinearProgressIndicator(),
          if (_dupResult != null)
            _ResultLine(passed: _dupPassed, observed: _dupResult!),
          const SizedBox(height: 16),
          Text('Pagination and batch write (Extra Spice #6)', style: text.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _bulkRunning ? null : _seed,
                child: const Text('Seed 120 messages'),
              ),
              OutlinedButton(
                onPressed: _bulkRunning ? null : _clearMine,
                child: const Text('Delete all my messages (one batch)'),
              ),
            ],
          ),
          if (_bulkRunning) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
          if (_bulkStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_bulkStatus!),
            ),
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.check, required this.onRun});
  final _Check check;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(check.action, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Expected: ${check.expected}'),
            if (check.running) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
            if (check.observed != null)
              _ResultLine(passed: check.passed, observed: check.observed!),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: check.running ? null : onRun,
                child: const Text('Run'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.passed, required this.observed});
  final bool? passed;
  final String observed;

  @override
  Widget build(BuildContext context) {
    final label = passed == null ? 'SKIPPED' : (passed! ? 'PASS' : 'FAIL');
    final color = passed == null
        ? Colors.grey.shade700
        : (passed! ? Colors.green.shade800 : Colors.red.shade800);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: 'RESULT: $label  ',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          TextSpan(text: 'Observed: $observed'),
        ]),
      ),
    );
  }
}

/// Reached from the sign-in screen while signed out.
class SignedOutProbeScreen extends StatefulWidget {
  const SignedOutProbeScreen({super.key});

  @override
  State<SignedOutProbeScreen> createState() => _SignedOutProbeScreenState();
}

class _SignedOutProbeScreenState extends State<SignedOutProbeScreen> {
  final RulesProbeService _probe = RulesProbeService();
  bool _running = false;
  String? _observed;
  bool? _passed;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _observed = null;
    });
    final o = await _probe.signedOutRead();
    if (!mounted) return;
    setState(() {
      _running = false;
      _observed = _describe(o);
      _passed = _deniedByRules(o);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signed-out rules check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Action: read the messages collection from the server with no '
              'signed-in user (the app UI never allows this).'),
          const SizedBox(height: 4),
          const Text('Expected: Denied: permission-denied'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _running ? null : _run,
            child: const Text('Run signed-out read'),
          ),
          if (_running) const LinearProgressIndicator(),
          if (_observed != null) _ResultLine(passed: _passed, observed: _observed!),
        ],
      ),
    );
  }
}
