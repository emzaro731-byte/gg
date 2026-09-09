import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Passwordless phone authentication for GG Messenger.
///
/// Supabase sends the OTP. The same flow is used for first-time registration
/// and subsequent logins: entering a new phone number creates the user when
/// Supabase Auth is configured to allow new users.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  bool codeSent = false;
  bool loading = false;
  bool resending = false;
  String? error;
  String? notice;

  String get phone => phoneController.text.trim();
  String get otp => otpController.text.trim();

  bool _validPhone(String value) {
    final normalized = value.replaceAll(RegExp(r'[\s\-()]'), '');
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized);
  }

  Future<void> sendCode() async {
    final value = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!_validPhone(value)) {
      setState(() {
        error = 'Enter your full international number, e.g. +2348012345678';
        notice = null;
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: value,
        shouldCreateUser: true,
      );
      if (!mounted) return;
      setState(() {
        codeSent = true;
        notice = 'We sent a one-time code to $value.';
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verifyCode() async {
    final value = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!_validPhone(value)) {
      setState(() => error = 'Enter a valid international phone number.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() => error = 'Enter the 6-digit code from your SMS.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: value,
        token: otp,
        type: OtpType.sms,
      );
      // AuthGate listens for the authenticated session and opens HomePage.
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'The code could not be verified. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resendCode() async {
    if (loading || resending) return;
    final value = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!_validPhone(value)) return;

    setState(() {
      resending = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: value,
        shouldCreateUser: true,
      );
      if (mounted) setState(() => notice = 'A new one-time code was sent.');
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not resend the code.');
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  void changeNumber() {
    setState(() {
      codeSent = false;
      otpController.clear();
      error = null;
      notice = null;
    });
  }

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.forum_rounded, size: 54, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'GG Messenger',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    codeSent
                        ? 'Enter the one-time code we sent you'
                        : 'Sign in or create an account with your phone',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: phoneController,
                    enabled: !codeSent && !loading,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+234 801 234 5678',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                    onSubmitted: (_) => !codeSent && !loading ? sendCode() : null,
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      autofocus: true,
                      onSubmitted: (_) => loading ? null : verifyCode(),
                      decoration: const InputDecoration(
                        labelText: '6-digit OTP',
                        hintText: '123456',
                        prefixIcon: Icon(Icons.verified_user_rounded),
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        notice!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: loading ? null : (codeSent ? verifyCode : sendCode),
                      icon: Icon(codeSent ? Icons.verified_rounded : Icons.sms_rounded),
                      label: Text(
                        loading
                            ? 'Please wait...'
                            : codeSent
                                ? 'Verify & continue'
                                : 'Send OTP',
                      ),
                    ),
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: loading || resending ? null : resendCode,
                          child: Text(resending ? 'Sending...' : 'Resend code'),
                        ),
                        const Text(' • '),
                        TextButton(
                          onPressed: loading ? null : changeNumber,
                          child: const Text('Change number'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'No password required. Your phone number is verified with a one-time code.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
