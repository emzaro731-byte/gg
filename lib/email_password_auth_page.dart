import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gg_brand.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _homeRedirectUrl =
      'https://emzaro731-byte.github.io/gg/';

  final emailController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isSignUp = false;
  bool forgotPassword = false;
  bool loading = false;
  bool obscurePassword = true;
  String? error;
  String? notice;

  String get email => emailController.text.trim().toLowerCase();
  String get username => usernameController.text.trim().toLowerCase();
  String get password => passwordController.text;
  String get confirmPassword => confirmPasswordController.text;

  bool get validEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  bool get validUsername =>
      RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(username);

  Future<bool> _usernameTaken(String value) async {
    final row = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('username', value)
        .maybeSingle();
    return row != null;
  }

  void _setError(String value) {
    if (!mounted) return;
    setState(() {
      error = value;
      notice = null;
    });
  }

  Future<void> submit() async {
    if (!validEmail) {
      _setError('Enter a valid email address.');
      return;
    }

    if (forgotPassword) {
      await resetPassword();
      return;
    }

    if (password.length < 8) {
      _setError('Password must be at least 8 characters.');
      return;
    }

    if (isSignUp) {
      if (!validUsername) {
        _setError(
          'Username must be 3–30 characters: lowercase letters, numbers, _ or .',
        );
        return;
      }
      if (password != confirmPassword) {
        _setError('Passwords do not match.');
        return;
      }
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      if (isSignUp && await _usernameTaken(username)) {
        if (mounted) {
          setState(() {
            error = 'Username is taken. Please choose another username.';
          });
        }
        return;
      }

      final auth = Supabase.instance.client.auth;

      if (isSignUp) {
        final response = await auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: _homeRedirectUrl,
          data: {
            'username': username,
            'display_name': username,
          },
        );

        if (!mounted) return;
        setState(() {
          notice = response.session != null
              ? 'Account created as @$username.'
              : 'Account created as @$username. Check your email to confirm your account.';
        });
      } else {
        await auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on SocketException {
      if (mounted) {
        setState(() {
          error =
              'No internet connection. Check your connection and try again. Your saved data remains available offline.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) {
        final message = e.toString().toLowerCase();
        setState(() {
          error = message.contains('failed host lookup') ||
                  message.contains('socketexception') ||
                  message.contains('connection')
              ? 'Unable to connect to GG Messenger. Check your internet connection and try again.'
              : 'Authentication failed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    if (!validEmail) {
      _setError('Enter a valid email address.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: _homeRedirectUrl,
      );
      if (mounted) {
        setState(() => notice = 'Password reset link sent to $email.');
      }
    } on SocketException {
      if (mounted) {
        setState(() => error =
            'No internet connection. Connect to the internet and try again.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not send the password reset link. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      isSignUp = !isSignUp;
      forgotPassword = false;
      error = null;
      notice = null;
    });
  }

  void _toggleForgotPassword() {
    setState(() {
      forgotPassword = !forgotPassword;
      isSignUp = false;
      error = null;
      notice = null;
      passwordController.clear();
      confirmPasswordController.clear();
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  const GGBrandMark(size: 108, showGlow: true),
                  const SizedBox(height: 18),
                  Text(
                    'GG Messenger',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    forgotPassword
                        ? 'Reset your password'
                        : isSignUp
                            ? 'Create your account'
                            : 'Sign in with your email and password',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: emailController,
                    enabled: !loading,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_rounded),
                    ),
                  ),
                  if (isSignUp && !forgotPassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      enabled: !loading,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'yourname',
                        prefixText: '@',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !loading,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: forgotPassword ? 'New password' : 'Password',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => obscurePassword = !obscurePassword);
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (isSignUp || forgotPassword) ...[
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
                  const SizedBox(height: 14),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        notice!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: loading ? null : submit,
                      icon: Icon(
                        forgotPassword
                            ? Icons.mark_email_read_rounded
                            : isSignUp
                                ? Icons.person_add_rounded
                                : Icons.login_rounded,
                      ),
                      label: Text(
                        loading
                            ? 'Please wait...'
                            : forgotPassword
                                ? 'Send reset link'
                                : isSignUp
                                    ? 'Create account'
                                    : 'Sign in',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: loading ? null : _toggleForgotPassword,
                    child: Text(
                      forgotPassword
                          ? 'Back to sign in'
                          : 'Forgot password?',
                    ),
                  ),
                  if (!forgotPassword)
                    TextButton(
                      onPressed: loading ? null : _toggleMode,
                      child: Text(
                        isSignUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
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

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  bool loading = false;
  bool obscure = true;
  String? error;
  String? notice;

  Future<void> updatePassword() async {
    final password = passwordController.text;
    final confirm = confirmController.text;

    if (password.length < 8) {
      setState(() => error = 'Your new password must be at least 8 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => error = 'Passwords do not match.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
      notice = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) {
        setState(() => notice = 'Password changed successfully.');
      }
    } on SocketException {
      if (mounted) {
        setState(() => error =
            'No internet connection. Connect to the internet and try again.');
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not change your password.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  const GGBrandMark(size: 108, showGlow: true),
                  const SizedBox(height: 18),
                  Text(
                    'Reset password',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a new password for your GG Messenger account.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: passwordController,
                    enabled: !loading,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    enabled: !loading,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        notice!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: loading ? null : updatePassword,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(
                        loading ? 'Saving...' : 'Set new password',
                      ),
                    ),
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
