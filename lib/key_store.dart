import 'key_store_stub.dart' if (dart.library.js_interop) 'key_store_web.dart' as impl;

/// Where the developer's SimpleAPI key is remembered between visits.
/// In the browser this is localStorage; the key is never part of the source.
abstract class KeyStore {
  String? read();
  void write(String key);
  void clear();
}

/// Keeps the key in memory only (used by tests and as a fallback).
class MemoryKeyStore implements KeyStore {
  MemoryKeyStore([this._key]);
  String? _key;

  @override
  String? read() => _key;

  @override
  void write(String key) => _key = key;

  @override
  void clear() => _key = null;
}

KeyStore createKeyStore() => impl.createKeyStore();
