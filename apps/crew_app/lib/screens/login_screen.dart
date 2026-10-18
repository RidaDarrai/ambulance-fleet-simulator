import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/tokens.dart';
import '../widgets/atoms.dart';

/// Login — email + password, staff accounts only (screen spec §1).
///
/// No self sign-up: accounts are provisioned (`crew@sim.local` / `crew12345`
/// in the demo). Errors never reveal whether an account exists. Lockouts and
/// the dispatcher hotline link give the human path.
class LoginScreen extends StatefulWidget {
  final AppState state;
  const LoginScreen({super.key, required this.state});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'crew@sim.local');
  final _password = TextEditingController(text: 'crew12345');
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  AppState get state => widget.state;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // signIn is async (demo simulates latency; Firebase authenticates).
    final ok = await state.signIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _error = "Email or password is incorrect. Try again or call dispatch.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.of(context).size.width >= 720;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              // Centered card on tablet (spec §1): max 420dp.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.sessionExpired) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.10),
                        borderRadius:
                            BorderRadius.circular(AppColors.radiusMd),
                      ),
                      child: Text(
                        'Your session expired — sign in again. Your active '
                        'mission is safe on the server.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.danger),
                      ),
                    ),
                    gapH(14),
                  ],
                  if (wide) ...[
                    Icon(Icons.local_hospital_rounded,
                        size: 56, color: theme.colorScheme.primary),
                    gapH(12),
                  ],
                  Text('Ambulance Crew',
                      style: theme.textTheme.headlineLarge,
                      textAlign: TextAlign.center),
                  gapH(4),
                  Text('Sign in with your crew account',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center),
                  gapH(28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Email'),
                    onSubmitted: (_) => _submit(),
                  ),
                  gapH(14),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    gapH(12),
                    Text(_error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.danger)),
                  ],
                  gapH(24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Sign in'),
                  ),
                  gapH(8),
                  TextButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Dialing dispatch hotline 150…'))),
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    label: const Text("Can't sign in? Call dispatch"),
                  ),
                  gapH(24),
                  Center(
                      child: Text('v0.1',
                          style: theme.textTheme.labelSmall)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
