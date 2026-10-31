import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// window.open(url, '_blank') through dart:js_interop.
void openUrl(String url) {
  globalContext.callMethod<JSAny?>('open'.toJS, url.toJS, '_blank'.toJS, 'noopener'.toJS);
}
