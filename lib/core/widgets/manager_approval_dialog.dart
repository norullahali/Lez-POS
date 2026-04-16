import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../database/app_database.dart';

/// Request manager approval via a 4-8 digit PIN code.
/// Returns the [User] object of the approver if successful, or null if cancelled mapping to [requiredPermission].
class ManagerApprovalDialog extends ConsumerStatefulWidget {
  final String requiredPermission;
  final String actionDescription;

  const ManagerApprovalDialog({
    super.key,
    required this.requiredPermission,
    required this.actionDescription,
  });

  @override
  ConsumerState<ManagerApprovalDialog> createState() => _ManagerApprovalDialogState();
}

class _ManagerApprovalDialogState extends ConsumerState<ManagerApprovalDialog> {
  String _pin = '';
  bool _isLoading = false;
  String? _error;

  void _onKeyPress(String key) {
    if (_pin.length < 8) {
      setState(() {
        _pin += key;
        _error = null;
      });
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_pin.length < 4) {
      setState(() => _error = 'الرمز يجب أن يكون 4 أرقام على الأقل');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = await ref.read(authProvider.notifier).validatePinForPermission(_pin, widget.requiredPermission);
      if (mounted) {
        if (user != null) {
          Navigator.pop(context, user);
        } else {
          setState(() {
            _error = 'الرمز غير صحيح أو لا توجد صلاحية للموافقة';
            _pin = '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'حدث خطأ أثناء التحقق: $e';
          _pin = '';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.posPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security_rounded, color: AppColors.warning, size: 48),
            const SizedBox(height: 16),
            const Text(
              'مطلوب موافقة المشرف',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.actionDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            
            // PIN Display
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.posPanelLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _error != null ? AppColors.error : Colors.transparent),
              ),
              alignment: Alignment.center,
              child: Text(
                '*' * _pin.length,
                style: TextStyle(
                  color: _error != null ? AppColors.error : Colors.white,
                  letterSpacing: 8,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ),
            
            const SizedBox(height: 24),
            
            // Numeric Keypad
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                if (index == 9) {
                  return _KeypadBtn(
                    label: 'مسح',
                    icon: Icons.backspace_outlined,
                    color: Colors.white24,
                    onTap: _onDelete,
                  );
                } else if (index == 10) {
                  return _KeypadBtn(label: '0', onTap: () => _onKeyPress('0'));
                } else if (index == 11) {
                  return _KeypadBtn(
                    label: 'دخول',
                    color: AppColors.primary,
                    onTap: _submit,
                  );
                }
                return _KeypadBtn(
                  label: '${index + 1}',
                  onTap: () => _onKeyPress('${index + 1}'),
                );
              },
            ),

            const SizedBox(height: 16),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('إلغاء الأمر', style: TextStyle(color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeypadBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback onTap;

  const _KeypadBtn({
    required this.label,
    this.icon,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.posPanelLight,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: icon != null
              ? Icon(icon, color: Colors.white)
              : Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
