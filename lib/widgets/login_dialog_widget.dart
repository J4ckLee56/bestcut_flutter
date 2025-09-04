import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../theme/cursor_theme.dart';

class LoginDialogWidget extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  final VoidCallback? onCancel;

  const LoginDialogWidget({
    super.key,
    this.onLoginSuccess,
    this.onCancel,
  });

  @override
  State<LoginDialogWidget> createState() => _LoginDialogWidgetState();
}

class _LoginDialogWidgetState extends State<LoginDialogWidget> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;
  bool _isSignUpMode = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        decoration: CursorTheme.containerDecoration(
          backgroundColor: CursorTheme.backgroundPrimary,
          borderColor: CursorTheme.borderPrimary,
          borderRadius: CursorTheme.radiusMedium,
          elevated: true,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.all(CursorTheme.spacingL),
              decoration: BoxDecoration(
                color: CursorTheme.backgroundSecondary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(CursorTheme.radiusMedium),
                  topRight: Radius.circular(CursorTheme.radiusMedium),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: CursorTheme.cursorBlue,
                      borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: CursorTheme.textPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: CursorTheme.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSignUpMode ? '회원가입' : '로그인',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: CursorTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _isSignUpMode 
                            ? 'BestCut 계정을 생성하세요'
                            : 'BestCut에 로그인하세요',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: CursorTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(
                      Icons.close,
                      color: CursorTheme.textSecondary,
                      size: 20,
                    ),
                    tooltip: '닫기',
                  ),
                ],
              ),
            ),
            
            // 폼 내용
            Padding(
              padding: const EdgeInsets.all(CursorTheme.spacingL),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 이메일 입력
                    _buildTextField(
                      controller: _emailController,
                      label: '이메일',
                      hint: 'example@email.com',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '이메일을 입력해주세요';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                          return '올바른 이메일 형식을 입력해주세요';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: CursorTheme.spacingM),
                    
                    // 비밀번호 입력
                    _buildTextField(
                      controller: _passwordController,
                      label: '비밀번호',
                      hint: '비밀번호를 입력하세요',
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          color: CursorTheme.textSecondary,
                          size: 20,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '비밀번호를 입력해주세요';
                        }
                        if (_isSignUpMode && value.length < 6) {
                          return '비밀번호는 6자 이상이어야 합니다';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: CursorTheme.spacingL),
                    
                    // 로그인/회원가입 버튼
                    _buildPrimaryButton(),
                    
                    const SizedBox(height: CursorTheme.spacingM),
                    
                    // 모드 전환 버튼
                    _buildModeToggleButton(),
                    
                    // 비밀번호 재설정 (로그인 모드에서만)
                    if (!_isSignUpMode) ...[
                      const SizedBox(height: CursorTheme.spacingM),
                      _buildForgotPasswordButton(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: CursorTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: CursorTheme.spacingS),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: CursorTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CursorTheme.textTertiary,
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: CursorTheme.backgroundSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
              borderSide: BorderSide(color: CursorTheme.borderSecondary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
              borderSide: BorderSide(color: CursorTheme.borderSecondary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
              borderSide: BorderSide(color: CursorTheme.cursorBlue, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
              borderSide: BorderSide(color: CursorTheme.error),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: CursorTheme.spacingM,
              vertical: CursorTheme.spacingM,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            CursorTheme.cursorBlue,
            CursorTheme.cursorBlue.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
        boxShadow: [
          BoxShadow(
            color: CursorTheme.cursorBlue.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
          onTap: _isLoading ? null : _handleSubmit,
          child: Center(
            child: _isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(CursorTheme.textPrimary),
                  ),
                )
              : Text(
                  _isSignUpMode ? '회원가입' : '로그인',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: CursorTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggleButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isSignUpMode ? '이미 계정이 있으신가요?' : '계정이 없으신가요?',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: CursorTheme.textTertiary,
          ),
        ),
        const SizedBox(width: CursorTheme.spacingS),
        GestureDetector(
          onTap: () {
            setState(() {
              _isSignUpMode = !_isSignUpMode;
            });
          },
          child: Text(
            _isSignUpMode ? '로그인' : '회원가입',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CursorTheme.cursorBlue,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordButton() {
    return Center(
      child: GestureDetector(
        onTap: _handleForgotPassword,
        child: Text(
          '비밀번호를 잊으셨나요?',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: CursorTheme.cursorBlue,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic> result;
      
      if (_isSignUpMode) {
        result = await _authService.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        result = await _authService.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }

      if (result['success']) {
        if (kDebugMode) print('✅ 로그인/회원가입 성공');
        widget.onLoginSuccess?.call();
        Navigator.of(context).pop();
      } else {
        _showErrorSnackBar(result['message']);
      }
    } catch (e) {
      if (kDebugMode) print('❌ 로그인/회원가입 오류: $e');
      _showErrorSnackBar('오류가 발생했습니다: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_emailController.text.trim().isEmpty) {
      _showErrorSnackBar('이메일을 먼저 입력해주세요');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _authService.resetPassword(_emailController.text.trim());
      
      if (result['success']) {
        _showSuccessSnackBar(result['message']);
      } else {
        _showErrorSnackBar(result['message']);
      }
    } catch (e) {
      if (kDebugMode) print('❌ 비밀번호 재설정 오류: $e');
      _showErrorSnackBar('오류가 발생했습니다: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CursorTheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CursorTheme.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
