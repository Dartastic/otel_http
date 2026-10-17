<!-- dartastic-header:start -->
# OpenTelemetry instrumentation for `http`

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenTelemetry Specification](https://img.shields.io/badge/OpenTelemetry-Specification-blueviolet)](https://opentelemetry.io/docs/specs/otel/)

`otel_http` is an [OpenTelemetry](https://opentelemetry.io/) instrumentation for `http` that
easily adds standard observability to applications that use `http`.  This package depends on 
[dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api).

This package can be used with any OTel backend because it's compliant with the OpenTelemetry Specification.

This package supports Android, iOS, Linux, macOS, Web and Windows, for versions of `http` that support those platforms. It is WASM-ready.

This Apache-2.0 package is professionally maintained and supported with 💙 by Michael Bushe,
Dart and Flutter Maintainer at OpenTelemetry and the creator of [dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry)
and [dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api). This package is professionally supported by
[Dartastic.io](https://dartastic.io).

---
## Dartastic.io: AI Code Healing and Real User Monitoring for Flutter

**See what your users experience. Find problems with Flutter apps in production. Fix them with AI.**

[Dartastic.io](https://dartastic.io) brings AI code healing, real user monitoring, and OpenTelemetry observability together in one platform built for Dart and Flutter. (Patents pending)

![Dartastic AI answering "Why did crashes jump after the last release?" over a Flutter App Health dashboard](https://dartastic.io/img/pub-dev/HomePageCrashesQuestion.png)

### Dartastic AI — From Production Problems to Code Fixes

Dartastic AI analyzes production telemetry alongside your application source code to diagnose problems and propose fixes.

- **Investigate production issues** using crashes, errors, traces, metrics, and real user telemetry.
- **Find the offending code** by connecting observed problems with your application's source in Dartastic Pub or your source code repos.
- **Generate code patches** that address the underlying problems.
- **Create actionable issues** in your issue tracker, complete with findings and the proposed code patch.

### Dartastic RUM — See What Your Users See

Understand how people actually experience your Flutter application.

- **Replay user sessions** in the Dartastic Observatory session player.
- **Choose your replay fidelity**, from privacy-preserving widget outlines to pixel-level reproductions of the user experience.
- **Investigate real user problems** using session replay and production observability data.

![Dartastic RUM Session Replay](https://dartastic.io/img/pub-dev/session-replay.png)

### Dartastic Observatory — Observability Built for Flutter

A complete observability backend where Flutter and Dart are first-class citizens.

- **Flutter-specific dashboards** for application performance, health, and reliability.
- **Alerts and notifications** through email, Slack, and PagerDuty.
- **Dartastic Cloud Observatory** — Start with a 30-day free trial on isolated, shared infrastructure, as low as $39/mo.
- **Dartastic Hosted Observatory** — Run the observability stack in a private managed environment, sized from Mini to Enterprise XL.
- **Dartastic Self-Hosted Observatory** — The whole platform inside your own network. Your keys, your cluster, with nothing leaving your perimeter.

### Dartastic Native OTel Runtime — Native OpenTelemetry Performance

Collect production telemetry without burdening Flutter's main isolate.

- **Native OpenTelemetry runtime** that moves telemetry processing off the main isolate.
- **Native crash reporting** for problems that Dart can't catch.
- **Widget performance diagnostics** to identify janky widgets.
- **On-device PII filtering** before sensitive data leaves your application.
- **Source-level error diagnostics** powered by the Dartastic Symbolizer API.
- **Platform-native metrics** for iOS, Android, and Linux, including iOS MetricKit and Android Vitals.
- **OpenTelemetry compatibility** — Send telemetry to Dartastic Observatory or any OpenTelemetry platform.

### Dartastic Labs — OpenTelemetry Integrations

Instrument more of your application without writing everything yourself.

- **650+ open-source integrations** for Dart and Flutter libraries and services, including Dio, Shelf, Logger, Anthropic, AWS, Azure, and Stripe. Look for otel_* on pub.dev.

### More Dartastic Tools

**[Dartastic Pub](https://dartastic.io/pub)**

A private Dart package registry for sharing packages and plugins with your team, partners, and customers.

**[Dartastic Symbolizer](https://dartastic.io/symbolizer)**

Turn production errors into lines of source code through a web API, while keeping your source code artifacts private.

### Professional Support and Training

Dartastic.io offers commercial support for the open-source `dartastic_opentelemetry` and `dartastic_opentelemetry_api` packages and the complete Dartastic product suite.

- **Professional support** with available around-the-clock coverage and response times under four hours on qualifying plans.
- **OpenTelemetry training** for teams instrumenting Dart, Flutter, mobile, and web applications.

### Open Standards. No Mandatory Backend.

The Dartastic OpenTelemetry API and SDK are open source and standards-based. You can use them independently of Dartastic's commercial services and send telemetry to any compatible OpenTelemetry backend.

Dartastic's commercial products add native performance, advanced diagnostics, session replay, AI-assisted remediation, and managed observability services.

**[Explore Dartastic.io](https://dartastic.io)**

---
<!-- dartastic-header:end -->

OpenTelemetry client instrumentation for [`package:http`](https://pub.dev/packages/http),
Dart's official cross-platform HTTP client. Built on the
[Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry).

Wrap any `http.Client` and every request gets:

- A `CLIENT`-kind span around the call.
- The full HTTP semantic-convention attribute set
  (`http.request.method`, `url.full`, `server.address`,
  `http.response.status_code`, …).
- W3C `traceparent` / `tracestate` / `baggage` headers injected so
  any downstream service that also speaks OTel joins the same trace.
- Exception recording (`recordException` + `error.type` + `Error`
  status) on transport failures and 4xx / 5xx responses.

## Why

`package:http` is the foundation HTTP client for the Dart and
Flutter ecosystems. A missing client span here is a blind spot in
every higher-level integration that talks to a backend — auth,
analytics relays, GraphQL, Firebase callable functions, you name it.
This package is the one place you wire OTel into HTTP so the entire
stack above it inherits trace context for free.

The bridge is **opt-in**: the OTel SDK does not depend on
`package:http`. Add this package only when you want the integration.

## ⚠️ Self-recursion: don't instrument your OTLP/HTTP export client

OTLP/HTTP export is itself HTTP. The dartastic SDK's built-in
OTLP/HTTP exporter sends via `package:http`. If you somehow wire
OTLP export through an `OTelHttpClient`-wrapped client, every span
you export creates an HTTP call that the wrapper turns into a new
span, which gets exported, which makes another call — classic
instrumentation recursion.

**You're safe by default** — the SDK's exporter creates its own
private `http.Client` that your `OTelHttpClient` isn't attached
to. The risk only appears if you manually wire OTLP/HTTP export
through a `Client` you also wrapped. If that's your setup, do
one of:

1. **Don't wrap that client.** Use a separate, plain `http.Client`
   for OTLP traffic.
2. **Wrap export calls in the suppression helper:**
   ```dart
   import 'package:otel_http/otel_http.dart';

   await runWithoutHttpInstrumentationAsync(() async {
     await myOtlpClient.post(...);
   });
   ```
   The wrapper checks a zone-scoped flag and skips span creation
   AND header injection. Sync variant:
   `runWithoutHttpInstrumentation`.

## Usage

```dart
import 'package:otel_http/otel_http.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  await OTel.initialize(serviceName: 'my-app');

  // Wrap any http.Client. The OTel client is itself a `BaseClient`,
  // so it slots in anywhere a `Client` is expected.
  final client = OTelHttpClient(http.Client());

  // Inside a server-side / handler span so the client span has a parent.
  await OTel.tracer().startActiveSpanAsync<void>(
    name: 'serve-request',
    fn: (_) async {
      final r = await client.get(
        Uri.parse('https://api.example.com/users/42'),
      );
      print(r.statusCode);
    },
  );

  client.close();
  await OTel.shutdown();
}
```

Outbound requests carry trace context automatically:

```
GET /users/42 HTTP/1.1
Host: api.example.com
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
tracestate: ...
```

## Span shape

Follows the OTel
[HTTP client semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/#http-client).

| Attribute                       | Source                                | When set      |
| ------------------------------- | ------------------------------------- | ------------- |
| `http.request.method`           | uppercased `request.method`           | always        |
| `url.full`                      | `request.url` (userinfo redacted)     | always        |
| `url.scheme`                    | `request.url.scheme`                  | always        |
| `url.path`                      | `request.url.path`                    | when present  |
| `url.query`                     | `request.url.query`                   | when present  |
| `server.address`                | `request.url.host`                    | when present  |
| `server.port`                   | `request.url.port`                    | when explicit |
| `http.request.body.size`        | `request.contentLength`               | when set      |
| `user_agent.original`           | `User-Agent` request header           | when present  |
| `http.response.status_code`     | `response.statusCode`                 | on response   |
| `http.response.body.size`       | `response.contentLength`              | when set      |
| `error.type`                    | `runtimeType` of underlying error     | on exception  |

- **Span name** defaults to `{HTTP_METHOD}` (e.g. `GET`). Per the
  OTel spec the recommended name is `{METHOD} {url-template}` when
  the template is known; pass `spanNameBuilder` if you have one.
- **Span kind** is `CLIENT`.
- **Span status** is set to `Error` for 4xx / 5xx responses and any
  thrown exception; otherwise it follows the SDK default.

Userinfo in the URL (`https://alice:secret@host/...`) is redacted
to `https://REDACTED:REDACTED@host/...` per the spec's "URL.full
SHOULD NOT contain credentials" requirement.

## Configuration

| Constructor arg | Default | Effect |
|---|---|---|
| `tracer` | `OTel.tracerProvider().getTracer('otel_http')` | The tracer that emits the spans. |
| `spanNameBuilder` | `(req) => req.method.toUpperCase()` | Override the span name (e.g. inject a URL template). |
| `recordRequestBodySize` | `true` | Set `http.request.body.size` from `contentLength`. |
| `recordResponseBodySize` | `true` | Set `http.response.body.size` from `contentLength`. |
| `ignoreUrlPatterns` | `const []` | Requests whose full URL matches any pattern (`String` substring or `RegExp`) are not instrumented at all — no span, no header injection. |

```dart
OTelHttpClient(
  http.Client(),
  ignoreUrlPatterns: [
    RegExp(r'/v1/(traces|metrics|logs)$'), // OTLP upload endpoints
    'analytics.example.com',
  ],
)
```

If your telemetry exporter shares this client, ignore its endpoints —
otherwise every export becomes a span, which is itself exported (the
double-count trap). `ignoreUrlPatterns` is configuration for known
URLs; the zone-scoped suppression below stays the right tool for
call-site scoping.

## Body sizes

`http.{request,response}.body.size` come from `BaseRequest.contentLength`
and `StreamedResponse.contentLength`, not by reading the body, so
there's no performance hit and no PII risk. Pass
`recordRequestBodySize: false` / `recordResponseBodySize: false`
if your app sets `contentLength` to something synthetic.

## Composing with other clients

Because `OTelHttpClient` is a `http.BaseClient` that wraps another
`http.Client`, it composes naturally with other client decorators
(retry, auth, caching). Put `OTelHttpClient` **outermost** so its
span encloses everything the inner clients do:

```dart
final client = OTelHttpClient(
  RetryClient(
    AuthClient(http.Client()),
  ),
);
```

That way retries appear as repeated outbound requests inside one
span (or use per-attempt span events if you wire your retry client
to emit them).

## Caveats

- The client calls `OTel.tracerProvider().getTracer(...)` in its
  constructor — `OTel.initialize()` must have run first.
- `OTelHttpClient.close()` closes the wrapped inner client. If you
  share an inner client across multiple wrappers, manage its
  lifecycle yourself.

## License

Apache 2.0 — see `LICENSE`.
