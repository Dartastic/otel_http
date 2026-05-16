// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:http/http.dart' as http;
import 'package:otel_http/otel_http.dart';
import 'package:test/test.dart';

/// A fake `http.Client` that returns a canned response and records
/// the request it saw — lets us assert on the headers we injected
/// without doing real network I/O.
class _FakeClient extends http.BaseClient {
  _FakeClient({
    this.statusCode = 200,
    this.reasonPhrase = 'OK',
    this.exception,
  });

  final int statusCode;
  final String reasonPhrase;
  final Object? exception;

  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    // Realize the body stream so the wrapped client's `finalize` is
    // exercised, matching what a real adapter would do.
    await request.finalize().fold<int>(0, (acc, chunk) => acc + chunk.length);
    if (exception != null) {
      // ignore: only_throw_errors
      throw exception!;
    }
    final bytes = Uint8List.fromList(utf8.encode('{}'));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      contentLength: bytes.length,
      request: request,
      headers: const {'content-type': 'application/json'},
      reasonPhrase: reasonPhrase,
    );
  }
}

/// In-memory exporter so we can assert what the client produced.
class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;

  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrs(Span span) =>
    {for (final a in span.attributes.toList()) a.key: a.value};

void main() {
  group('OTelHttpClient', () {
    late _MemorySpanExporter exporter;
    late _FakeClient inner;
    late OTelHttpClient client;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'http-otel-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
      inner = _FakeClient();
      client = OTelHttpClient(inner);
    });

    tearDown(() async {
      client.close();
      await OTel.shutdown();
      await OTel.reset();
    });

    test('GET emits a CLIENT span with the full HTTP semconv set', () async {
      await client
          .get(Uri.parse('https://api.example.com/users/42?expand=true'));

      expect(exporter.spans, hasLength(1));
      final span = exporter.spans.single;
      expect(span.name, equals('GET'));
      expect(span.kind, equals(SpanKind.client));
      final attrs = _attrs(span);
      expect(attrs['http.request.method'], equals('GET'));
      expect(attrs['url.full'],
          equals('https://api.example.com/users/42?expand=true'));
      expect(attrs['url.scheme'], equals('https'));
      expect(attrs['url.path'], equals('/users/42'));
      expect(attrs['url.query'], equals('expand=true'));
      expect(attrs['server.address'], equals('api.example.com'));
      expect(attrs['http.response.status_code'], equals(200));
      expect(span.status, isNot(equals(SpanStatusCode.Error)));
    });

    test('injects W3C traceparent into outbound request headers', () async {
      await client.get(Uri.parse('https://api.example.com/things'));

      final tp = inner.lastRequest!.headers['traceparent'];
      expect(tp, isNotNull);
      // version-traceId-spanId-flags = 2 + 32 + 16 + 2 + 3 dashes = 55
      expect(tp!.length, equals(55));
      expect(tp.startsWith('00-'), isTrue);
    });

    test('500 response sets span status to Error', () async {
      client.close();
      inner = _FakeClient(statusCode: 500, reasonPhrase: 'Internal');
      client = OTelHttpClient(inner);

      await client.get(Uri.parse('https://api.example.com/boom'));

      final span = exporter.spans.single;
      expect(span.status, equals(SpanStatusCode.Error));
      expect(_attrs(span)['http.response.status_code'], equals(500));
    });

    test('404 response sets span status to Error', () async {
      client.close();
      inner = _FakeClient(statusCode: 404, reasonPhrase: 'Not Found');
      client = OTelHttpClient(inner);

      await client.get(Uri.parse('https://api.example.com/missing'));

      final span = exporter.spans.single;
      expect(span.status, equals(SpanStatusCode.Error));
    });

    test('transport exception records exception event + Error status',
        () async {
      client.close();
      final boom = http.ClientException('connection reset');
      inner = _FakeClient(exception: boom);
      client = OTelHttpClient(inner);

      expect(
        () => client.get(Uri.parse('https://api.example.com/dead')),
        throwsA(equals(boom)),
      );
      // Span end happens inside the catch — give it a microtask to flush.
      await Future<void>.delayed(Duration.zero);

      final span = exporter.spans.single;
      expect(span.status, equals(SpanStatusCode.Error));
      expect(_attrs(span)['error.type'], equals('ClientException'));
      final events = span.spanEvents ?? [];
      expect(
        events.any((e) => e.name == 'exception'),
        isTrue,
        reason: 'recordException should have emitted an exception event',
      );
    });

    test('URL userinfo is redacted in url.full', () async {
      await client.get(
        Uri.parse('https://alice:secret@api.example.com/me'),
      );

      final attrs = _attrs(exporter.spans.single);
      expect(
        attrs['url.full'],
        equals('https://REDACTED:REDACTED@api.example.com/me'),
      );
    });

    test('POST body_size from Content-Length when present', () async {
      await client.post(
        Uri.parse('https://api.example.com/things'),
        headers: {'content-type': 'application/json'},
        body: '{"hello":"world"}',
      );

      final attrs = _attrs(exporter.spans.single);
      // package:http auto-sets Content-Length for string bodies.
      expect(attrs['http.request.body.size'], equals(17));
    });

    test('spanNameBuilder lets caller override the span name', () async {
      client.close();
      client = OTelHttpClient(
        inner,
        spanNameBuilder: (req) => '${req.method.toUpperCase()} /users/{id}',
      );

      await client.get(Uri.parse('https://api.example.com/users/42'));

      expect(exporter.spans.single.name, equals('GET /users/{id}'));
    });

    test('inherits parent span when called inside startActiveSpan', () async {
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'parent',
        fn: (_) async {
          await client.get(Uri.parse('https://api.example.com/x'));
        },
      );

      final child = exporter.spans.firstWhere((s) => s.name == 'GET');
      final parent = exporter.spans.firstWhere((s) => s.name == 'parent');
      expect(
        child.parentSpanContext?.spanId,
        equals(parent.spanContext.spanId),
        reason: 'GET span should be a child of the parent active span',
      );
    });

    test('runWithoutHttpInstrumentationAsync skips span + header injection',
        () async {
      await runWithoutHttpInstrumentationAsync(() async {
        await client.get(Uri.parse('https://api.example.com/x'));
      });

      expect(
        exporter.spans,
        isEmpty,
        reason: 'suppression scope should bypass the wrapper entirely',
      );
      // Inner client still got the request, but no traceparent was
      // injected — proves the suppression path doesn't touch headers.
      expect(inner.lastRequest, isNotNull);
      expect(inner.lastRequest!.headers['traceparent'], isNull);
    });
  });
}
