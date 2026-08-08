// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Runnable demo of `otel_http` against a local OTLP-capable backend.
///
/// Start any OTLP-compatible backend that also serves a trace UI,
/// exposing ports 3000 (UI), 4317 (OTLP/gRPC) and 4318 (OTLP/HTTP).
///
/// Then run this app:
///   dart run bin/main.dart
///
/// Open the trace UI (http://localhost:3000 for the container above),
/// search for service `http-otel-example-app`, and you'll see one
/// trace per scenario — happy path, 4xx, 5xx, transport failure, and
/// a POST with a body, each demonstrating a different code path
/// through the client and the resulting span attributes.
library;

import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:http/http.dart' as http;
import 'package:otel_http/otel_http.dart';

const _serviceName = 'http-otel-example-app';
// 4318 = OTLP/HTTP default port (the SDK's default protocol is
// `http/protobuf`). Use 4317 only with `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`.
const _defaultEndpoint = 'http://localhost:4318';

Future<void> main(List<String> args) async {
  final endpoint =
      Platform.environment['OTEL_EXPORTER_OTLP_ENDPOINT'] ?? _defaultEndpoint;

  print('==> exporting to $endpoint as $_serviceName');

  await OTel.initialize(
    serviceName: _serviceName,
    serviceVersion: '0.0.1',
    endpoint: endpoint,
  );

  final client = OTelHttpClient(http.Client());
  final tracer = OTel.tracer();

  await tracer.startActiveSpanAsync<void>(
    name: 'run-scenarios',
    fn: (_) async {
      await _scenario('happy-path-get', () async {
        // httpbin.org/anything echoes the request — predictable 200.
        final r = await client.get(Uri.parse('https://httpbin.org/anything'));
        print('  ok  ${r.statusCode}');
      });

      await _scenario('not-found-404', () async {
        final r = await client.get(Uri.parse('https://httpbin.org/status/404'));
        print('  expected 4xx: ${r.statusCode}');
      });

      await _scenario('server-error-500', () async {
        final r = await client.get(Uri.parse('https://httpbin.org/status/500'));
        print('  expected 5xx: ${r.statusCode}');
      });

      await _scenario('transport-failure', () async {
        try {
          // DNS that won't resolve — fast, deterministic transport failure.
          await client.get(Uri.parse('http://example.invalid/'));
        } on http.ClientException catch (e) {
          print('  expected transport failure: ${e.message}');
        } on SocketException catch (e) {
          print('  expected transport failure: ${e.message}');
        }
      });

      await _scenario('post-with-body', () async {
        final r = await client.post(
          Uri.parse('https://httpbin.org/anything'),
          headers: {'content-type': 'application/json'},
          body: '{"hello":"otel"}',
        );
        print('  ok  ${r.statusCode}');
      });
    },
  );

  client.close();

  print('==> flushing + shutting down');
  await OTel.tracerProvider().forceFlush();
  await OTel.shutdown();
  print('==> done. open your trace UI (http://localhost:3000 for the '
      'backend started above), service = $_serviceName');
}

Future<void> _scenario(String name, FutureOr<void> Function() body) async {
  print('--> $name');
  await OTel.tracer().startActiveSpanAsync<void>(
    name: name,
    fn: (_) async {
      try {
        await body();
      } catch (e) {
        // Already recorded by the client as a child span; we just
        // don't let the scenario span bubble it up.
        print('  caught: $e');
      }
    },
  );
}
