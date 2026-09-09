import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final otpController = TextEditingController();

  bool isSignUp = false;
  bool codeSent = false;
  bool loading = false;
  bool resending = false;
  bool obscurePassword = true;
  String? error;
  String? notice;

  String get email => emailController.text.trim().toLowerCase();
  String get password => passwordController.text;
  String get confirmPassword => confirmPasswordController.text;
  String get otp => otpController.text.trim();

  bool get validEmail => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  Future<void> submit() async {
    if (!validEmail) {
      setState(() {
        error = 'Enter a valid email address.';
        notice = null;
      });
      return;
    }
    if (password.length < 8) {
      setState(() {
        error = 'Password must be at least 8 characters.';
        notice = null;
      });
      return;
    }
    if (isSignUp && password != confirmPassword) {
      setState(() {
        error = 'Passwords do not match.';
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
      final auth = Supabase.instance.client.auth;
      if (isSignUp) {
        final response = await auth.signUp(email: email, password: password);
        if (!mounted) return;

        if (response.session != null) {
          // Email confirmation is disabled; AuthGate will open the app.
          return;
        }

        setState(() {
          codeSent = true;
          notice = 'We sent an 8-digit verification code to $email.';
        });
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Authentication failed. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verifyEmail() async {
    if (!validEmail) {
      setState(() => error = 'Enter a valid email address.');
      return;
    }
    if (!RegExp(r'^\d{8}$').hasMatch(otp)) {
      setState(() => error = 'Enter the 8-digit verification code.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.signup,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'The verification code could not be verified.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resendVerification() async {
    if (loading || resending || !validEmail) return;

    setState(() {
      resending = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (mounted) setState(() => notice = 'A new 8-digit verification code was sent.');
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not resend the verification code.');
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  void backToLogin() {
    setState(() {
      codeSent = false;
      isSignUp = false;
      otpController.clear();
      confirmPasswordController.clear();
      error = null;
      notice = null;
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
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
                      gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
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
                        ? 'Verify your email address'
                        : isSignUp
                            ? 'Create your account with email and password'
                            : 'Sign in with your email and password',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: emailController,
                    enabled: !codeSent && !loading,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.email_rounded),
                    ),
                  ),
                  if (!codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      enabled: !loading,
                      obscureText: obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscurePassword = !obscurePassword),
                          icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                    ),
                    if (isSignUp) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmPasswordController,
                        enabled: !loading,
                        obscureText: obscurePassword,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                    ],
                  ],
                  if (codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      autofocus: true,
                      onSubmitted: (_) => loading ? null : verifyEmail(),
                      decoration: const InputDecoration(
                        labelText: '8-digit verification code',
                        hintText: '12345678',
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
                      onPressed: loading ? null : (codeSent ? verifyEmail : submit),
                      icon: Icon(codeSent ? Icons.verified_rounded : (isSignUp ? Icons.person_add_rounded : Icons.login_rounded)),
                      label: Text(
                        loading
                            ? 'Please wait...'
                            : codeSent
                                ? 'Verify email'
                                : isSignUp
                                    ? 'Create account'
                                    : 'Sign in',
                      ),
                    ),
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: loading || resending ? null : resendVerification,
                          child: Text(resending ? 'Sending...' : 'Resend code'),
                        ),
                        const Text(' • '),
                        TextButton(
                          onPressed: loading ? null : backToLogin,
                          child: const Text('Back to login'),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => setState(() {
                                isSignUp = !isSignUp;
                                error = null;
                                notice = null;
                              }),
                      child: Text(isSignUp ? 'Already have an account? Sign in' : 'New here? Create an account'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    isSignUp
                        ? 'Your email verification code is 8 digits. Never share it with anyone.'
                        : 'Use the email and password you registered with.',
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
