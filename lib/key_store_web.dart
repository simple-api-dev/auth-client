import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'key_store.dart';

const _storageName = 'simpleapi_auth_client_key';

KeyStore createKeyStore() => _LocalStorageKeyStore();

/// Browser localStorage, reached through dart:js_interop (no extra package).
/// Falls back to memory when the browser blocks storage.
class _LocalStorageKeyStore implements KeyStore {
  final _fallback = MemoryKeyStore();

  JSObject get _storage => globalContext['localStorage']! as JSObject;

  @override
  String? read() {
    try {
      final value = _storage.callMethod<JSAny?>('getItem'.toJS, _storageName.toJS);
      return (value as JSString?)?.toDart ?? _fallback.read();
    } catch (_) {
      return _fallback.read();
    }
  }

  @override
  void write(String key) {
    _fallback.write(key);
    try {
      _storage.callMethod<JSAny?>('setItem'.toJS, _storageName.toJS, key.toJS);
    } catch (_) {}
  }

  @override
  void clear() {
    _fallback.clear();
    try {
      _storage.callMethod<JSAny?>('removeItem'.toJS, _storageName.toJS);
    } catch (_) {}
  }
}
