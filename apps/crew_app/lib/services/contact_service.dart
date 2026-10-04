import 'package:url_launcher/url_launcher.dart';

const kDispatchHotline = '+212522000000';

Future<bool> launchCall(String number) async {
  final uri = Uri(scheme: 'tel', path: number);
  try {
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {}
  return false;
}
