import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final otpController = TextEditingController();
  bool isSignUp = false, codeSent = false, loginChallenge = false, forgotPassword = false, loading = false, resending = false, obscurePassword = true;
  String? error, notice;
  String get email => emailController.text.trim().toLowerCase();
  String get username => usernameController.text.trim().toLowerCase();
  String get password => passwordController.text;
  String get confirmPassword => confirmPasswordController.text;
  String get otp => otpController.text.trim();
  bool get validEmail => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  bool get validUsername => RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(username);

  Future<void> submit() async {
    if (!validEmail) return _setError('Enter a valid email address.');
    if (forgotPassword) return sendRecoveryCode();
    if (password.length < 8) return _setError('Password must be at least 8 characters.');
    if (isSignUp) {
      if (!validUsername) return _setError('Username must be 3–30 characters: letters, numbers, _ or .');
      if (password != confirmPassword) return _setError('Passwords do not match.');
    }
    setState(() { loading = true; error = null; notice = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (isSignUp) {
        final response = await auth.signUp(email: email, password: password, data: {'username': username});
        final user = response.user;
        if (user != null) {
          try {
            await Supabase.instance.client.from('profiles').upsert({'id': user.id, 'username': username, 'updated_at': DateTime.now().toUtc().toIso8601String()});
          } on PostgrestException catch (e) {
            if (e.code == '23505' || e.message.toLowerCase().contains('duplicate')) throw const AuthException('That username is already taken. Choose another username.');
            rethrow;
          }
        }
        if (!mounted) return;
        if (response.session != null) return;
        setState(() { codeSent = true; loginChallenge = false; forgotPassword = false; notice = 'We sent an 8-digit verification code to $email.'; });
      } else {
        await auth.signInWithPassword(email: email, password: password);
        await auth.signOut();
        await auth.signInWithOtp(email: email, shouldCreateUser: false);
        if (!mounted) return;
        otpController.clear();
        setState(() { codeSent = true; loginChallenge = true; forgotPassword = false; notice = 'Password accepted. We sent a new 8-digit OTP to $email.'; });
      }
    } on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'Authentication failed. Please try again.'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> sendRecoveryCode() async {
    if (!validEmail) return _setError('Enter a valid email address.');
    setState(() { loading = true; error = null; notice = null; });
    try { await Supabase.instance.client.auth.signInWithOtp(email: email, shouldCreateUser: false); if (mounted) setState(() { codeSent = true; forgotPassword = true; notice = 'A fresh 8-digit password-reset OTP was sent to $email.'; }); }
    on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'Could not send the password-reset OTP. Please try again.'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> verifyEmail() async {
    if (!validEmail) return _setError('Enter a valid email address.');
    if (!RegExp(r'^\d{8}$').hasMatch(otp)) return _setError('Enter the 8-digit verification code.');
    if (forgotPassword && password.length < 8) return _setError('Enter a new password of at least 8 characters.');
    if (forgotPassword && password != confirmPassword) return _setError('New passwords do not match.');
    setState(() { loading = true; error = null; notice = null; });
    try {
      final auth = Supabase.instance.client.auth;
      await auth.verifyOTP(email: email, token: otp, type: loginChallenge || forgotPassword ? OtpType.email : OtpType.signup);
      if (forgotPassword) {
        await auth.updateUser(UserAttributes(password: password));
        if (!mounted) return;
        setState(() { forgotPassword = false; codeSent = false; loginChallenge = false; passwordController.clear(); confirmPasswordController.clear(); otpController.clear(); notice = 'Password changed successfully. You are now signed in.'; });
      }
    } on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'The verification code could not be verified.'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> resendVerification() async {
    if (loading || resending || !validEmail) return;
    setState(() { resending = true; error = null; notice = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (forgotPassword || loginChallenge) await auth.signInWithOtp(email: email, shouldCreateUser: false); else await auth.resend(type: OtpType.signup, email: email);
      if (mounted) setState(() => notice = forgotPassword ? 'A new 8-digit password-reset OTP was sent.' : loginChallenge ? 'A new 8-digit login OTP was sent.' : 'A new 8-digit verification code was sent.');
    } on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'Could not resend the code.'); }
    finally { if (mounted) setState(() => resending = false); }
  }

  void startForgotPassword() => setState(() { forgotPassword = true; isSignUp = false; codeSent = false; loginChallenge = false; passwordController.clear(); confirmPasswordController.clear(); otpController.clear(); error = null; notice = null; });
  void backToLogin() => setState(() { codeSent = false; loginChallenge = false; forgotPassword = false; isSignUp = false; otpController.clear(); confirmPasswordController.clear(); usernameController.clear(); error = null; notice = null; });
  void _setError(String value) { if (mounted) setState(() { error = value; notice = null; }); }

  @override
  void dispose() { emailController.dispose(); usernameController.dispose(); passwordController.dispose(); confirmPasswordController.dispose(); otpController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]), shape: BoxShape.circle), child: Icon(Icons.forum_rounded, size: 54, color: scheme.onPrimary)),
      const SizedBox(height: 18),
      Text('GG Messenger', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(codeSent ? (forgotPassword ? 'Reset your password' : loginChallenge ? 'Verify your login' : 'Verify your email address') : forgotPassword ? 'Enter your email to receive an OTP' : isSignUp ? 'Create your account with a unique username' : 'Sign in with email, password and OTP', textAlign: TextAlign.center),
      const SizedBox(height: 30),
      TextField(controller: emailController, enabled: !codeSent && !loading, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_rounded)),),
      if (!codeSent && isSignUp) ...[
        const SizedBox(height: 12),
        TextField(controller: usernameController, enabled: !loading, autocorrect: false, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username', hintText: 'yourname', prefixText: '@', prefixIcon: Icon(Icons.alternate_email_rounded)),),
      ],
      if (!codeSent && (!forgotPassword || passwordController.text.isNotEmpty)) ...[
        const SizedBox(height: 12),
        TextField(controller: passwordController, enabled: !loading, obscureText: obscurePassword, decoration: InputDecoration(labelText: forgotPassword ? 'New password' : 'Password', prefixIcon: const Icon(Icons.lock_rounded), suffixIcon: IconButton(onPressed: () => setState(() => obscurePassword = !obscurePassword), icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off)))),
        if (isSignUp || forgotPassword) ...[const SizedBox(height: 12), TextField(controller: confirmPasswordController, enabled: !loading, obscureText: obscurePassword, decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline_rounded)))],
      ],
      if (codeSent) ...[
        if (forgotPassword) ...[const SizedBox(height: 12), TextField(controller: passwordController, enabled: !loading, obscureText: obscurePassword, decoration: const InputDecoration(labelText: 'New password', prefixIcon: Icon(Icons.lock_rounded))), const SizedBox(height: 12), TextField(controller: confirmPasswordController, enabled: !loading, obscureText: obscurePassword, decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_outline_rounded)))],
        const SizedBox(height: 12), TextField(controller: otpController, keyboardType: TextInputType.number, maxLength: 8, autofocus: true, onSubmitted: (_) => loading ? null : verifyEmail(), decoration: InputDecoration(labelText: '8-digit ${forgotPassword ? 'password-reset OTP' : loginChallenge ? 'login OTP' : 'verification code'}', hintText: '12345678', prefixIcon: const Icon(Icons.verified_user_rounded), counterText: '')),
      ],
      const SizedBox(height: 14),
      if (notice != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(notice!, textAlign: TextAlign.center, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600))),
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error))),
      SizedBox(width: double.infinity, height: 54, child: FilledButton.icon(onPressed: loading ? null : (codeSent ? verifyEmail : submit), icon: Icon(codeSent ? Icons.verified_rounded : forgotPassword ? Icons.mark_email_read_rounded : isSignUp ? Icons.person_add_rounded : Icons.login_rounded), label: Text(loading ? 'Please wait...' : codeSent ? (forgotPassword ? 'Verify & reset password' : 'Verify & continue') : forgotPassword ? 'Send OTP' : isSignUp ? 'Create account' : 'Sign in & send OTP'))),
      if (codeSent) Row(mainAxisAlignment: MainAxisAlignment.center, children: [TextButton(onPressed: loading || resending ? null : resendVerification, child: Text(resending ? 'Sending...' : 'Resend OTP')), const Text(' • '), TextButton(onPressed: loading ? null : backToLogin, child: const Text('Back'))]) else if (forgotPassword) TextButton(onPressed: loading ? null : backToLogin, child: const Text('Back to sign in')) else ...[TextButton(onPressed: loading ? null : startForgotPassword, child: const Text('Forgot password?')), TextButton(onPressed: loading ? null : () => setState(() { isSignUp = !isSignUp; error = null; notice = null; }), child: Text(isSignUp ? 'Already have an account? Sign in' : 'New here? Create an account'))],
      const SizedBox(height: 12),
      if (isSignUp && !codeSent) Text('Username must be unique. Use 3–30 lowercase letters, numbers, _ or .', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ])))));
  }
}
