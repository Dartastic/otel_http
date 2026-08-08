// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Integration test: drive an OTelHttpClient request against the
/// backend container's UI port (3000 — always responds), then poll
/// the trace query API to verify the client span arrived with the
/// expected HTTP semconv attributes.
///
/// Skipped when no OTLP backend is reachable. Bring one up first:
///   any OTLP-compatible backend exposing a trace-by-id query API on
///   :3200, a UI on :3000, and OTLP on :4317/:4318
///
/// Env vars:
///   OTLP_ENDPOINT — OTLP/HTTP endpoint (default http://localhost:4318)
///   TRACE_API_URL — trace query API base (default http://localhost:3200)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:http/http.dart' as http;
import 'package:otel_http/otel_http.dart';
import 'package:test/test.dart';

const _defaultOtlp = 'http://localhost:4318';
const _defaultOtlpPort = 4318;
const _defaultTraceApi = 'http://localhost:3200';

// Target the backend container itself on its UI port — always
// reachable when the stack is up, doesn't depend on httpbin.org.
const _selfTargetUrl = 'http://localhost:3000/';

void main() {
  group('OTLP backend end-to-end', () {
    final otlpEndpoint = Platform.environment['OTLP_ENDPOINT'] ?? _defaultOtlp;
    final traceApiUrl =
        Platform.environment['TRACE_API_URL'] ?? _defaultTraceApi;

    test('OTelHttpClient span appears in the backend with HTTP semconv',
        () async {
      // Skip unless BOTH the trace query API and the OTLP port are
      // reachable. /ready alone can match an unrelated service.
      final traceApiOk = await _traceApiReachable(traceApiUrl);
      final otlpOk = await _portOpen(otlpEndpoint);
      if (!traceApiOk || !otlpOk) {
        markTestSkipped(
          'Backend not reachable (traces=$traceApiOk otlp=$otlpOk) — start '
          'any OTLP-compatible backend with a trace query API on :3200, a '
          'UI on :3000 and OTLP on :4317/:4318, then rerun.',
        );
        return;
      }

      await OTel.reset();
      await OTel.initialize(
        serviceName: 'http-otel-itest',
        serviceVersion: '0.0.1',
        endpoint: otlpEndpoint,
      );

      final client = OTelHttpClient(http.Client());

      late String traceIdHex;
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'itest-root',
        fn: (rootSpan) async {
          traceIdHex = rootSpan.spanContext.traceId.hexString;
          try {
            await client.get(Uri.parse(_selfTargetUrl));
          } on Exception {
            // Even if the request fails (the UI may return a redirect
            // chain, etc.), the client span is what we're verifying.
          }
        },
      );

      client.close();
      await OTel.tracerProvider().forceFlush();
      await OTel.shutdown();

      final trace = await _pollBackendForTrace(
        traceApiUrl: traceApiUrl,
        traceIdHex: traceIdHex,
        timeout: const Duration(seconds: 30),
      );
      expect(
        trace,
        isNotNull,
        reason: 'Backend never returned trace $traceIdHex',
      );

      final spans = <Map<String, dynamic>>[];
      for (final batch in (trace!['batches'] as List<dynamic>? ?? const [])) {
        final scopeSpans =
            (batch as Map<String, dynamic>)['scopeSpans'] as List<dynamic>? ??
                const [];
        for (final ss in scopeSpans) {
          final raw = (ss as Map<String, dynamic>)['spans'] as List<dynamic>? ??
              const [];
          for (final s in raw) {
            spans.add(s as Map<String, dynamic>);
          }
        }
      }
      expect(spans, isNotEmpty);

      final clientSpan = spans.firstWhere(
        (s) => s['name'] == 'GET',
        orElse: () =>
            throw StateError('no GET client span found in trace $traceIdHex'),
      );
      final attrKeys = <String>{
        for (final a in clientSpan['attributes'] as List<dynamic>? ?? const [])
          (a as Map<String, dynamic>)['key'] as String,
      };
      expect(attrKeys, contains('http.request.method'));
      expect(attrKeys, contains('url.full'));
      expect(attrKeys, contains('server.address'));
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}

Future<bool> _traceApiReachable(String traceApiUrl) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    final req = await c.getUrl(Uri.parse('$traceApiUrl/ready'));
    final resp = await req.close().timeout(const Duration(seconds: 2));
    await resp.drain<void>();
    c.close();
    return resp.statusCode == 200;
  } on Exception {
    return false;
  }
}

Future<bool> _portOpen(String endpoint) async {
  try {
    final uri = Uri.parse(endpoint);
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.hasPort ? uri.port : _defaultOtlpPort;
    final socket =
        await Socket.connect(host, port, timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } on Exception {
    return false;
  }
}

Future<Map<String, dynamic>?> _pollBackendForTrace({
  required String traceApiUrl,
  required String traceIdHex,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  final client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final req = await client.getUrl(
          Uri.parse('$traceApiUrl/api/traces/$traceIdHex'),
        );
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final parsed = jsonDecode(body) as Map<String, dynamic>;
          final batches = parsed['batches'] as List<dynamic>? ?? const [];
          if (batches.isNotEmpty) return parsed;
        } else {
          await resp.drain<void>();
        }
      } on Exception {
        // Transient — keep polling.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    client.close();
  }
  return null;
}
