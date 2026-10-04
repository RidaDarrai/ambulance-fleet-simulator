import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = ProfileService();

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _bloodType = TextEditingController();
  final _allergies = TextEditingController();
  final _conditions = TextEditingController();
  final _contact = TextEditingController();

  bool _signUpMode = false;
  bool _busy = false;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _service.authChanges.listen((user) {
      if (user != null && !_loaded) _loadProfile();
      if (user == null) setState(() => _loaded = false);
    });
  }

  Future<void> _loadProfile() async {
    final data = await _service.loadProfile();
    if (data != null && mounted) {
      _bloodType.text = data['bloodType'] ?? '';
      _allergies.text = data['allergies'] ?? '';
      _conditions.text = data['conditions'] ?? '';
      _contact.text = data['emergencyContact'] ?? '';
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _submitAuth() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (_signUpMode) {
        await _service.signUp(_email.text.trim(), _password.text);
      } else {
        await _service.signIn(_email.text.trim(), _password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Authentication failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await _service.saveProfile(
      bloodType: _bloodType.text.trim(),
      allergies: _allergies.text.trim(),
      conditions: _conditions.text.trim(),
      emergencyContact: _contact.text.trim(),
    );
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _service.authChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return _buildAuthForm();
        if (!_loaded) return const Center(child: CircularProgressIndicator());
        return _buildProfileForm();
      },
    );
  }

  Widget _buildAuthForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Medical profile'),
            subtitle: const Text(
                'Sign in to store blood type, allergies and contacts'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        TextField(
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submitAuth,
          child: Text(_busy
              ? 'Please wait…'
              : (_signUpMode ? 'Create account' : 'Sign in')),
        ),
        TextButton(
          onPressed: () => setState(() => _signUpMode = !_signUpMode),
          child: Text(_signUpMode
              ? 'Already have an account? Sign in'
              : 'No account? Sign up'),
        ),
      ],
    );
  }

  Widget _buildProfileForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Medical profile',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _bloodType,
          decoration: const InputDecoration(labelText: 'Blood type'),
        ),
        TextField(
          controller: _allergies,
          decoration: const InputDecoration(labelText: 'Critical allergies'),
          maxLines: 2,
        ),
        TextField(
          controller: _conditions,
          decoration: const InputDecoration(labelText: 'Chronic conditions'),
          maxLines: 2,
        ),
        TextField(
          controller: _contact,
          decoration: const InputDecoration(labelText: 'Emergency contact'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save profile'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _service.signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
