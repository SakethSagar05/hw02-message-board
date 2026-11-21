import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/app_exception.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/validators.dart';
import 'board_screen.dart';

/// Signed in is not enough: the board opens only once users/{uid} exists
/// with all five required fields and the server has confirmed it.
/// If the record is missing (the profile write failed, or the app was closed
/// mid-registration) the user can complete it and retry for the same uid.
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.user, required this.auth});
  final User user;
  final AuthService auth;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  final UserService _users = UserService();
  late Stream<UserRecordSnapshot> _record;
  late final ProfileDraft? _draft = UserService.takeDraft(widget.user.email);

  @override
  void initState() {
    super.initState();
    _record = _users.watchRecord(widget.user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserRecordSnapshot>(
      stream: _record,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load your profile.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(
                          () => _record = _users.watchRecord(widget.user.uid)),
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: widget.auth.signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final state = snapshot.data!;
        if (state.isReady) {
          return BoardScreen(me: state.record!, auth: widget.auth);
        }
        if (state.record != null && !state.pending && !state.record!.isComplete) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your user record is incomplete.'),
                  TextButton(
                    onPressed: widget.auth.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          );
        }
        // Missing, or written locally and waiting for the server.
        return CompleteProfileScreen(
          user: widget.user,
          users: _users,
          auth: widget.auth,
          draft: _draft,
        );
      },
    );
  }
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.user,
    required this.users,
    required this.auth,
    this.draft,
  });

  final User user;
  final UserService users;
  final AuthService auth;

  /// Fields from the registration form; when present they are saved
  /// automatically and the form is only shown again if that save fails.
  final ProfileDraft? draft;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: widget.draft?.firstName);
  late final _lastName = TextEditingController(text: widget.draft?.lastName);
  late String _role = widget.draft?.role ?? userRoles.first;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.draft != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _save());
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.users.saveUserRecord(
        uid: widget.user.uid,
        draft: ProfileDraft(
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          role: _role,
        ),
      );
      // ProfileGate switches to the board when the server confirms.
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = _busy && _error == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your profile'),
        actions: [
          TextButton(onPressed: widget.auth.signOut, child: const Text('Sign out')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      saving
                          ? 'Saving your profile…'
                          : 'Finish your profile to open the board.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('Signed in as ${widget.user.email ?? widget.user.uid}'),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _firstName,
                      decoration: const InputDecoration(labelText: 'First name'),
                      validator: (v) => Validators.name(v, label: 'first name'),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _lastName,
                      decoration: const InputDecoration(labelText: 'Last name'),
                      validator: (v) => Validators.name(v, label: 'last name'),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: [
                        for (final r in userRoles)
                          DropdownMenuItem(value: r, child: Text(r)),
                      ],
                      onChanged: _busy ? null : (v) => setState(() => _role = v ?? _role),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_error == null ? 'Save profile' : 'Retry save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
