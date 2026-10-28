/// Client-side checks for quick feedback only. The server is authoritative and
/// repeats every check.
class Validators {
  const Validators._();

  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter your name';
    if (text.length > 100) return 'Use at most 100 characters';
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter your email';
    if (!text.contains('@') || text.startsWith('@') || text.endsWith('@')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// For login: only require that something was typed.
  static String? passwordPresent(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    return null;
  }

  /// For registration: mirrors the server rule (8 to 72 characters).
  static String? newPassword(String? value) {
    if (value == null || value.isEmpty) return 'Choose a password';
    if (value.length < 8) return 'Use at least 8 characters';
    if (value.length > 72) return 'Use at most 72 characters';
    return null;
  }

  static String? businessName(String? value) {
    final text = value?.trim() ?? '';
    if (text.length < 2) return 'Enter your business name';
    if (text.length > 120) return 'Use at most 120 characters';
    return null;
  }

  static String? invitationCode(String? value) {
    if ((value?.trim() ?? '').isEmpty) return 'Enter the invitation code';
    return null;
  }
}
