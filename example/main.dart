// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Minimal example: initialize OTel, wrap an `http.Client` in
/// [OTelHttpClient], make a request inside an active parent span,
/// then shut down cleanly.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:http/http.dart' as http;
import 'package:otel_http/otel_http.dart';

Future<void> main() async {
  await OTel.initialize(
    serviceName: 'http-otel-example',
    serviceVersion: '0.0.1',
  );

  final client = OTelHttpClient(
    http.Client(),
    // Never instrument telemetry-upload requests (no span, no
    // trace-context headers) — avoids the self-instrumentation loop
    // when an exporter shares this client.
    ignoreUrlPatterns: [RegExp(r'/v1/(traces|metrics|logs)$')],
  );

  // Wrap the outbound call in a parent span so the CLIENT span has
  // somewhere to be attached. In a real server, the parent would be
  // the incoming-request span from your framework's middleware.
  final tracer = OTel.tracer();
  await tracer.startActiveSpanAsync<void>(
    name: 'serve-request',
    fn: (_) async {
      final response =
          await client.get(Uri.parse('https://httpbin.org/status/200'));
      print('status: ${response.statusCode}');
    },
  );

  client.close();
  await OTel.shutdown();
}
