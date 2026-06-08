// signup_screen.dart
// Full registration: full name, email, unique username (checked live),
// and password. Calls backend.registerWithEmail which atomically reserves
// the username and creates the profile.

import 'package:flutter/material.dart';

import '../backend/backend.dart';

enum _NameState { idle, checking, available, taken, invalid }

class SignupScreen extends StatefulWidget {
  final GloveBackend backend;
  const SignupScreen({super.key, required this.backend});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  _NameState _nameState = _NameState.idle;
  String? _nameMessage;
  int _checkToken = 0;
  bool _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _onUsernameChanged(String raw) async {
    final formatError = UsernameService.validateFormat(raw);
    if (formatError != null) {
      setState(() {
        _nameState = _NameState.invalid;
        _nameMessage = formatError;
      });
      return;
    }
    setState(() {
      _nameState = _NameState.checking;
      _nameMessage = null;
    });

    final token = ++_checkToken; // ignore stale responses
    final free = await widget.backend.isUsernameAvailable(raw);
    if (!mounted || token != _checkToken) return;

    setState(() {
      _nameState = free ? _NameState.available : _NameState.taken;
      _nameMessage = free ? 'Available' : 'Already taken';
    });
  }

  Widget? get _usernameSuffix => switch (_nameState) {
        _NameState.checking => const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
                height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        _NameState.available =>
          const Icon(Icons.check_circle, color: Colors.green),
        _NameState.taken || _NameState.invalid =>
          const Icon(Icons.error, color: Colors.redAccent),
        _NameState.idle => null,
      };

  Future<void> _signup() async {
    setState(() => _busy = true);
    String? error;
    try {
      await widget.backend.registerWithEmail(
        fullName: _fullName.text,
        email: _email.text,
        password: _password.text,
        username: _username.text,
      );
      // Success → AuthGate switches to the shell; pop the auth stack.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    } on UsernameTakenException {
      error = 'That username is already taken.';
    } on ArgumentError catch (e) {
      error = e.message?.toString() ?? 'Please check your details.';
    } catch (e) {
      error = AuthService.describeAuthError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _fullName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _username,
              onChanged: _onUsernameChanged,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.alternate_email),
                suffixIcon: _usernameSuffix,
                helperText: _nameMessage,
                helperStyle: TextStyle(
                  color: _nameState == _NameState.available
                      ? Colors.green
                      : (_nameState == _NameState.idle ? null : Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (6+ characters)',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_busy || _nameState == _NameState.taken ||
                      _nameState == _NameState.invalid)
                  ? null
                  : _signup,
              child: Text(_busy ? 'Creating…' : 'Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
