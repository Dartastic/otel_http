// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

/// Zone key used to mark a region of code as "do not instrument with
/// the HTTP client wrapper." A `Symbol` so collisions can't happen and
/// the value doesn't cross isolate boundaries.
const Symbol _suppressKey = #otel_http_suppress;

/// Returns `true` when the current zone has opted out of HTTP OTel
/// instrumentation.
///
/// Exposed so [OTelHttpClient] (and tests) can consult it cheaply.
bool httpInstrumentationSuppressed() {
  return Zone.current[_suppressKey] == true;
}

/// Runs [body] in a zone where [OTelHttpClient.send] will skip span
/// creation and header injection.
///
/// The intended use case is the self-recursion hazard: the dartastic
/// SDK's built-in OTLP/HTTP exporter sends spans via `package:http`.
/// If you somehow point OTLP export at a client that has our
/// instrumentation attached, every span you export creates an HTTP
/// call that creates a new span that gets exported… infinite loop.
/// The SDK uses its own private `http.Client` internally so you're
/// safe by default; this helper exists for the edge case where you
/// wire export yourself.
///
/// ```dart
/// runWithoutHttpInstrumentationAsync(() async {
///   await otlpClient.post(...);
/// });
/// ```
///
/// The flag propagates through `Future` chains and `await` points
/// via the surrounding [Zone], so async work started inside [body]
/// is covered too.
T runWithoutHttpInstrumentation<T>(T Function() body) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}

/// Async variant of [runWithoutHttpInstrumentation]. Both forms are
/// safe to nest; they no-op once already inside a suppressed zone.
Future<T> runWithoutHttpInstrumentationAsync<T>(
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}

/// Zone key marking a request this package already instruments. Another
/// layer that would instrument the same request underneath (a wrapper of
/// `dart:io`'s `HttpClient`, or of the browser's `fetch`) checks it and
/// steps aside, so the request gets one client span, not two. The key is
/// the contract: a layer that cannot depend on this package reads
/// `Zone.current[#otel_http_instrumented]` directly.
const Symbol _instrumentedKey = #otel_http_instrumented;

/// Returns `true` while the current zone is sending a request that
/// [OTelHttpClient] instruments.
bool httpRequestInstrumented() {
  return Zone.current[_instrumentedKey] == true;
}

/// Runs [body] marked as instrumented: see [httpRequestInstrumented].
/// [OTelHttpClient] sends every request this way; a hand-written
/// instrumented client can do the same.
Future<T> runAsInstrumentedHttp<T>(Future<T> Function() body) {
  return runZoned(body, zoneValues: {_instrumentedKey: true});
}
