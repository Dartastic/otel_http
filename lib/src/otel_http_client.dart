// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:http/http.dart' as http;

import 'http_suppression.dart';

/// OpenTelemetry instrumentation for `package:http`.
///
/// Wraps any [http.Client] and emits a `CLIENT`-kind span per
/// request with the HTTP semantic-convention attributes
/// (`http.request.method`, `url.full`, `server.address`,
/// `http.response.status_code`, …), injects W3C `traceparent` /
/// `tracestate` / `baggage` headers so downstream services join the
/// same trace, and records exceptions / 4xx-5xx as `Error` status.
///
/// ```dart
/// import 'package:otel_http/otel_http.dart';
/// import 'package:http/http.dart' as http;
///
/// final client = OTelHttpClient(http.Client());
/// final response = await client.get(Uri.parse('https://api.example.com/users/42'));
/// ```
///
/// `OTelHttpClient` is a `http.BaseClient`, so every convenience
/// method (`get`/`post`/`put`/`patch`/`delete`/`head`/`read`/
/// `readBytes`) routes through the instrumented `send` automatically.
///
/// Span shape follows the OTel HTTP-client semantic conventions:
/// https://opentelemetry.io/docs/specs/semconv/http/http-spans/#http-client
class OTelHttpClient extends http.BaseClient {
  /// Creates a client that wraps [inner] with OTel instrumentation.
  ///
  /// - [tracer] — the tracer to use. Defaults to
  ///   `OTel.tracerProvider().getTracer('otel_http')`.
  /// - [spanNameBuilder] — overrides the default span name (`{METHOD}`).
  ///   Per spec, the recommended name is the HTTP method or
  ///   `{METHOD} {url-template}` when a route template is known.
  /// - [recordRequestBodySize] / [recordResponseBodySize] — set the
  ///   `http.{request,response}.body.size` attributes from the
  ///   `Content-Length` header when present. Defaults to `true`.
  OTelHttpClient(
    http.Client inner, {
    Tracer? tracer,
    String Function(http.BaseRequest request)? spanNameBuilder,
    this.recordRequestBodySize = true,
    this.recordResponseBodySize = true,
  })  : _inner = inner,
        _tracer =
            tracer ?? OTel.tracerProvider().getTracer('otel_http'),
        _spanNameBuilder = spanNameBuilder ?? _defaultSpanName,
        _traceContextPropagator = W3CTraceContextPropagator(),
        _baggagePropagator = W3CBaggagePropagator();

  final http.Client _inner;
  final Tracer _tracer;
  final String Function(http.BaseRequest request) _spanNameBuilder;
  final W3CTraceContextPropagator _traceContextPropagator;
  final W3CBaggagePropagator _baggagePropagator;

  /// Whether to set `http.request.body.size` from `Content-Length`.
  final bool recordRequestBodySize;

  /// Whether to set `http.response.body.size` from `Content-Length`.
  final bool recordResponseBodySize;

  static String _defaultSpanName(http.BaseRequest request) =>
      request.method.toUpperCase();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Bail before any span work if the caller has wrapped this
    // request in `runWithoutHttpInstrumentationAsync` (typically to
    // prevent OTLP-export-over-this-client recursion). Headers stay
    // untouched too — the inner client sees the request as-is.
    if (httpInstrumentationSuppressed()) {
      return _inner.send(request);
    }

    final uri = request.url;
    final method = request.method.toUpperCase();

    final attrs = <String, Object>{
      Http.requestMethod.key: method,
      Url.urlFull.key: _redactedUrl(uri),
      Url.urlScheme.key: uri.scheme,
      if (uri.host.isNotEmpty) ServerResource.serverAddress.key: uri.host,
      if (uri.hasPort) ServerResource.serverPort.key: uri.port,
      if (uri.path.isNotEmpty) Url.urlPath.key: uri.path,
      if (uri.hasQuery) Url.urlQuery.key: uri.query,
    };

    if (recordRequestBodySize) {
      final size = request.contentLength;
      if (size != null) {
        attrs[Http.requestBodySize.key] = size;
      }
    }

    final userAgent = _firstHeader(request.headers, 'user-agent');
    if (userAgent != null) {
      attrs[UserAgent.userAgentOriginal.key] = userAgent;
    }

    final span = _tracer.startSpan(
      _spanNameBuilder(request),
      kind: SpanKind.client,
      attributes: OTel.attributesFromMap(attrs),
    );

    // Inject W3C trace context + baggage into the outbound headers
    // so the receiving service joins this trace. `BaseRequest`'s
    // headers map is mutable — we modify it in-place.
    final ctx = Context.current.withSpan(span);
    final setter = _MapSetter(request.headers);
    _traceContextPropagator.inject(ctx, request.headers, setter);
    _baggagePropagator.inject(ctx, request.headers, setter);

    try {
      final response = await _inner.send(request);
      _finishWithResponse(span, response);
      return response;
    } on Object catch (error, stackTrace) {
      _finishWithError(span, error, stackTrace);
      rethrow;
    }
  }

  void _finishWithResponse(APISpan span, http.StreamedResponse response) {
    final extra = <Attribute<Object>>[
      OTel.attributeInt(Http.responseStatusCode.key, response.statusCode),
    ];
    if (response.statusCode >= 400) {
      span.setStatus(
        SpanStatusCode.Error,
        response.reasonPhrase ?? 'HTTP ${response.statusCode}',
      );
    }
    if (recordResponseBodySize && response.contentLength != null) {
      extra.add(OTel.attributeInt(
        Http.responseBodySize.key,
        response.contentLength!,
      ));
    }
    span.addAttributes(OTel.attributes(extra));
    span.end();
  }

  void _finishWithError(APISpan span, Object error, StackTrace stackTrace) {
    // error.type — runtime class of the underlying error (per OTel spec).
    span.addAttributes(
      OTel.attributes([
        OTel.attributeString(
          ErrorResource.errorType.key,
          error.runtimeType.toString(),
        ),
      ]),
    );

    // Spec order: recordException first, THEN setStatus.
    span.recordException(error, stackTrace: stackTrace);
    span.setStatus(SpanStatusCode.Error, error.toString());
    span.end();
  }

  @override
  void close() {
    _inner.close();
  }

  /// Returns the URL with any userinfo redacted, per OTel HTTP semconv
  /// guidance ("URL.full SHOULD NOT contain credentials").
  static String _redactedUrl(Uri uri) {
    if (uri.userInfo.isEmpty) return uri.toString();
    return uri.replace(userInfo: 'REDACTED:REDACTED').toString();
  }

  static String? _firstHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }
}

class _MapSetter implements TextMapSetter<String> {
  _MapSetter(this._carrier);

  final Map<String, String> _carrier;

  @override
  void set(String key, String value) {
    _carrier[key] = value;
  }
}
