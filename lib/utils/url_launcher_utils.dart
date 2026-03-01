import 'package:url_launcher/url_launcher.dart';

class UrlLauncherUtils {
  static Future<bool> launchExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    try {
      final launchedExternally = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launchedExternally) {
        return true;
      }

      return launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }
}