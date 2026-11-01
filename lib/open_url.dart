import 'open_url_stub.dart' if (dart.library.js_interop) 'open_url_web.dart' as impl;

/// Opens a link in a new browser tab (no url_launcher package needed).
typedef UrlOpener = void Function(String url);

UrlOpener createUrlOpener() => impl.openUrl;
