import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/mission_status.dart';
import '../core/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/atoms.dart';

/// Sign in / Create account (screen spec §13).
///
/// Phone (tel keyboard) → 6-digit OTP (auto-advance + paste). "Continue as
/// guest" is always visible and never blocks the app. Back returns to the
/// screen that prompted sign-in (destination preserved).
/// States: loading (button progress) · validation · wrong code · server
/// error · offline.
class SignInScreen extends StatefulWidget {
  final AppState state;
  const SignInScreen({super.key, required this.state});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController();
  final List<TextEditingController> _otp =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  int _step = 1; // 1 = phone, 2 = OTP
  bool _sending = false;
  bool _verifying = false;
  String? _error; // inline error under the active step
  int _resendSeconds = 30;
  Timer? _resendTimer;

  // Real phone-auth session state (null until Firebase sends a code).
  String? _verificationId;
  int? _resendToken;

  AppState get state => widget.state;

  /// Real auth only runs when Firebase initialized at boot; otherwise the
  /// screen falls back to the demo path so walkthroughs still work.
  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  @override
  void dispose() {
    _phone.dispose();
    for (final c in _otp) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  // ── Step 1: phone ────────────────────────────────────────────────────

  String? get _phoneError {
    if (_error != null && _step == 1) return _error;
    return null;
  }

  /// Normalizes the typed number to E.164. Numbers starting with `+` are
  /// taken as-is; otherwise we assume Morocco (+212) and drop a leading 0.
  String? _e164() {
    final raw = _phone.text.trim();
    if (raw.startsWith('+')) {
      final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
      return d.length >= 8 ? '+$d' : null;
    }
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length < 9) return null;
    if (d.startsWith('212')) return '+$d';
    if (d.startsWith('0')) return '+212${d.substring(1)}';
    return '+212$d';
  }

  Future<void> _sendCode() async {
    final e164 = _e164();
    if (e164 == null) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }
    setState(() {
      _error = null;
      _sending = true;
    });

    // Demo fallback (no Firebase at boot): fake the send.
    if (!_firebaseReady) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() {
        _sending = false;
        _step = 2;
      });
      _startResendCountdown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocus.first.requestFocus();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Code sent · demo code 123456')),
      );
      return;
    }

    // Real phone auth.
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: e164,
        forceResendingToken: _resendToken,
        verificationCompleted: (credential) async {
          // Android instant verification / SMS auto-retrieval.
          await _signInWithCredential(credential);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() {
            _sending = false;
            _error = _friendlyAuthError(e);
          });
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          _verificationId = verificationId;
          _resendToken = resendToken;
          setState(() {
            _sending = false;
            _step = 2;
          });
          _startResendCountdown();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _otpFocus.first.requestFocus();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Code sent to $e164')),
          );
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not send the code. Check your connection and retry.';
      });
    }
  }

  void _startResendCountdown() {
    _resendSeconds = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) t.cancel();
      });
    });
  }

  // ── Step 2: OTP ──────────────────────────────────────────────────────

  String get _code => _otp.map((c) => c.text).join();

  /// Distributes a pasted string across the boxes (paste support, §13).
  void _onOtpChanged(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() => _error = null);
    if (digits.length > 1) {
      // Paste / autofill of a full code.
      for (var i = 0; i < _otp.length; i++) {
        _otp[i].text = i < digits.length ? digits[i] : '';
      }
      final last = digits.length.clamp(0, _otp.length) - 1;
      if (last >= 0 && last < _otp.length - 1) {
        _otpFocus[last + 1].requestFocus();
      } else if (last >= 0) {
        _otpFocus[last].unfocus();
      }
      return;
    }
    _otp[index].text = digits;
    if (digits.isNotEmpty && index < _otp.length - 1) {
      _otpFocus[index + 1].requestFocus();
    }
    if (_code.length == _otp.length) _verify();
  }

  void _onOtpKey(int index, KeyEvent event) {
    // Backspace on an empty box steps back (spec §13 gestures).
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _otp[index].text.isEmpty &&
        index > 0) {
      _otpFocus[index - 1].requestFocus();
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });

    // Demo fallback (no Firebase at boot): accept the demo code.
    if (!_firebaseReady) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() => _verifying = false);
      if (_code == '123456') {
        state.signIn();
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Signed in (demo)')));
      } else {
        setState(() => _error = "That code doesn't match. "
            'Try again or request a new one.');
        _clearOtp();
      }
      return;
    }

    // Real phone auth.
    if (_verificationId == null) {
      setState(() {
        _verifying = false;
        _error = 'Request a new code.';
      });
      return;
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: _code,
    );
    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      state.signIn();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Signed in')));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _sending = false;
        _error = _friendlyAuthError(e);
      });
      _clearOtp();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = "That code doesn't match. Try again or request a new one.";
      });
      _clearOtp();
    }
  }

  void _clearOtp() {
    for (final c in _otp) {
      c.clear();
    }
    _otpFocus.first.requestFocus();
  }

  String _friendlyAuthError(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'That phone number isn\u2019t valid.',
        'invalid-verification-code' =>
          "That code doesn't match. Try again or request a new one.",
        'session-expired' || 'code-expired' =>
          'That code expired. Request a new one.',
        'too-many-requests' => 'Too many attempts. Try again in a moment.',
        'quota-exceeded' => 'SMS limit reached. Try again later.',
        'invalid-app-credential' || 'captcha-check-failed' =>
          'Verification failed. On web, add this number as a test number in '
              'the Firebase console (Auth \u2192 Phone \u2192 Phone numbers for '
              'testing), or use a real phone number.',
        'operation-not-allowed' =>
          'Phone sign-in isn\u2019t enabled in the Firebase console yet.',
        'billing-not-enabled' => 'Phone sign-in needs billing enabled.',
        'network-request-failed' => 'Network error. Check your connection.',
        'app-not-authorized' =>
          'Sign-in isn\u2019t configured for this app yet.',
        _ => 'Something went wrong (${e.code}). Please try again.',
      };

  void _resend() {
    if (_resendSeconds > 0) return;
    _sendCode(); // countdown restarts in the codeSent / demo path
  }

  void _continueAsGuest() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Continuing as guest — you can sign in anytime.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_step == 2) {
              setState(() {
                _step = 1;
                _error = null;
                _resendTimer?.cancel();
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(_step == 1 ? 'Sign in' : 'Enter code'),
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => AbsorbPointer(
          absorbing: _sending || _verifying,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.offline) ...[
                _offlineBanner(theme),
                gapH(16),
              ],
              _valueCard(theme),
              gapH(20),
              Text('Step $_step of 2', style: theme.textTheme.labelSmall),
              gapH(8),
              if (_step == 1) _phoneStep(theme) else _otpStep(theme),
              gapH(20),
              _submit(theme),
              gapH(4),
              TextButton(
                onPressed: _continueAsGuest,
                child: const Text('Continue as guest'),
              ),
              gapH(8),
              Center(
                child: TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Privacy policy — opens in browser'))),
                  child: const Text('Privacy policy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pieces ───────────────────────────────────────────────────────────

  Widget _offlineBanner(ThemeData theme) {
    final amber = context.statusColor(MissionStatus.pending);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: amber),
          gapW(10),
          Expanded(
            child: Text(
              "You're offline. Connect to sign in — you can keep using the "
              'app as a guest.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Value card on top (spec §13).
  Widget _valueCard(ThemeData theme) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.medicalSurface,
          border: Border.all(color: AppColors.medicalBorder),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.medical_information_outlined,
                size: 28, color: AppColors.primary),
            gapW(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Save medical info so crews see it sooner',
                      style: theme.textTheme.bodyLarge),
                  gapH(2),
                  Text('Blood type, allergies and contacts attach '
                      'automatically to every request.',
                      style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _phoneStep(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '06 61 23 45 67',
              errorText: _phoneError,
            ),
          ),
          gapH(8),
          // Consent line — no pre-ticked boxes (spec §13 microcopy).
          Text("We'll only use your number to identify your requests.",
              style: theme.textTheme.labelSmall),
        ],
      );

  Widget _otpStep(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter the 6-digit code sent to ${_phone.text}',
              style: theme.textTheme.bodySmall),
          gapH(14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _otp.length; i++)
                SizedBox(
                  width: 46,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      _onOtpKey(i, event);
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _otp[i],
                      focusNode: _otpFocus[i],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: etaDisplayStyle(size: 20),
                      decoration: InputDecoration(
                        counterText: '',
                        errorText: null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 12),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      ],
                      onChanged: (v) => _onOtpChanged(i, v),
                    ),
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            gapH(8),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.danger)),
          ],
          gapH(12),
          TextButton(
            onPressed: _resendSeconds > 0 ? null : _resend,
            child: Text(
              _resendSeconds > 0
                  ? 'Send a new code in 0:${_resendSeconds.toString().padLeft(2, '0')}'
                  : 'Send a new code',
            ),
          ),
        ],
      );

  Widget _submit(ThemeData theme) {
    final offline = state.offline;
    final busy = _sending || _verifying;
    final label = _step == 1
        ? 'Send code'
        : _verifying
            ? 'Verifying…'
            : 'Verify & sign in';
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: offline ? theme.colorScheme.outline : null,
        ),
        onPressed: busy || offline
            ? null
            : () => _step == 1 ? _sendCode() : _verify(),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
