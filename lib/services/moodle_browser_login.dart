/// A safe external-browser entry point for university-hosted Moodle SSO.
/// Opening this URL does not authorize Moodle Web Services access.
class MoodleBrowserLogin {
  const MoodleBrowserLogin._();

  static Uri? universityLoginUrl(String value) {
    final server = Uri.tryParse(value.trim());
    if (server == null ||
        server.scheme != 'https' ||
        !server.hasAuthority ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment ||
        server.pathSegments.any((part) => part == '..')) {
      return null;
    }
    final root = server.toString().endsWith('/')
        ? server
        : Uri.parse('${server.toString()}/');
    return root.resolve('login/index.php');
  }
}
