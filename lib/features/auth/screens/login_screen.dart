import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/mkes_primary_button.dart';
import '../../../shared/widgets/mkes_text_field.dart';
import '../repositories/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Please enter both email and password.');
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showError('Please enter a valid email address.');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    // Check if Supabase is initialized
    try {
      Supabase.instance.client;
    } catch (e) {
      _showError('Supabase not initialized. Please check your configuration.');
      debugPrint('Supabase initialization error: $e');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signIn(
        email: email,
        password: password,
      );
      // Note: AuthWrapper in main.dart handles navigation automatically 
      // by listening to authStateChanges.

    } on AuthException catch (e) {
      if (!mounted) return;
      // Provide more user-friendly error messages
      String errorMessage = e.message;
      if (e.message.contains('Invalid login credentials')) {
        errorMessage = 'Invalid email or password. Please try again.';
      } else if (e.message.contains('Email not confirmed')) {
        errorMessage = 'Please confirm your email address before logging in.';
      } else if (e.message.contains('User not found')) {
        errorMessage = 'No account found with this email address.';
      }
      _showError(errorMessage);
      debugPrint('AuthException: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      debugPrint('Login error: $e');
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email to reset password.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to send reset email. Verify your email address.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;
    final horizontalPadding =
        isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile;
    final cardPadding = isDesktop ? AppSpacing.lg : AppSpacing.md;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(horizontalPadding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.maxContentWidth,
              ),
              child: Column(
                children: [
                  _BrandHeader(isDesktop: isDesktop),
                  const SizedBox(height: AppSpacing.lg),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      border: Border.all(color: AppColors.outlineVariant),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 20,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 4,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primaryContainer,
                                  AppColors.secondaryContainer,
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(cardPadding),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Welcome Back', style: AppTypography.headlineMd),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Sign in to access your dashboard.',
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                MkesTextField(
                                  label: 'Email',
                                  controller: _emailController,
                                  hintText: 'you@example.com',
                                  prefixIcon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Password',
                                      style: AppTypography.labelCaps.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _handleForgotPassword,
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'Forgot Password?',
                                        style: AppTypography.labelCaps.copyWith(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                MkesTextField(
                                  controller: _passwordController,
                                  hintText: '••••••••',
                                  prefixIcon: Icons.lock_outlined,
                                  obscureText: _obscurePassword,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: AppColors.onSurfaceVariant,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() => _obscurePassword = !_obscurePassword);
                                    },
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                if (_isLoading)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                else
                                  MkesPrimaryButton(
                                    label: 'Sign In',
                                    icon: Icons.arrow_forward,
                                    onPressed: _handleLogin,
                                  ),
                                const SizedBox(height: AppSpacing.md),
                                Center(
                                  child: Text(
                                    'Contact your administrator for account access.',
                                    style: AppTypography.bodySm.copyWith(
                                      color: AppColors.outline,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final logoSize = isDesktop ? 96.0 : 80.0;
    return Column(
      children: [
        Hero(
          tag: 'mkes_logo',
          child: Image.asset(
            'assets/images/mkes_logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(height: isDesktop ? AppSpacing.md : AppSpacing.sm),
        Text(
          'MKES CARE+',
          textAlign: TextAlign.center,
          style: isDesktop
              ? AppTypography.displayLg
              : AppTypography.displayLg.copyWith(fontSize: 36, height: 44 / 36),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Clinical Management Platform',
          textAlign: TextAlign.center,
          style: AppTypography.bodyLg,
        ),
      ],
    );
  }
}
