# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0-wip]

### Changed

- Semantic conventions updated to the current OTel registry; no
  deprecated attribute keys are emitted (only the current
  `http.request.method`, never the legacy `http.method`).
- Dependency floors raised to `dartastic_opentelemetry ^1.1.0-beta.12` and
  `dartastic_opentelemetry_api ^1.0.0-rc.1`. The previous floors declared
  compatibility with API versions that predate the semconv enums this
  package uses and could not actually resolve-and-compile.
- `repository` URL corrected to the canonical `Dartastic` org casing so
  pub.dev repository verification succeeds.

### Added

- `ignoreUrlPatterns` — URL patterns (substring or `RegExp`)
  excluded from instrumentation entirely (no span, no header
  injection), e.g. telemetry-upload endpoints — closes the
  self-instrumentation double-count trap for exporters sharing the
  client. Zone-scoped suppression remains the call-site tool.

- `OTelHttpClient` — a `http.BaseClient` that wraps another
  `http.Client` and emits a `CLIENT`-kind span per request with the
  HTTP semantic-convention attributes set
  (`http.request.method`, `url.full`, `url.scheme`, `url.path`,
  `url.query`, `server.address`, `server.port`,
  `http.request.body.size`, `user_agent.original`,
  `http.response.status_code`, `http.response.body.size`).
- W3C `traceparent` / `tracestate` / `baggage` headers injected into
  outbound requests so downstream services join the same trace.
- 4xx / 5xx responses flip span status to `Error`. Thrown exceptions
  trigger `recordException` (with stack trace) and `setStatus(Error)`,
  in OTel-spec order, with `error.type` set to the exception's
  runtime class.
- URL `userInfo` (`https://alice:secret@host/...`) is redacted in
  `url.full` per the OTel HTTP semconv guidance.
- `spanNameBuilder` constructor option for callers that know a URL
  template (recommended span name is `{METHOD} {url-template}`).
- `runWithoutHttpInstrumentation` /
  `runWithoutHttpInstrumentationAsync` — zone-scoped suppression
  helpers. `OTelHttpClient.send` checks a zone flag at the top of
  every call and skips span creation AND header injection when
  set. Backs the self-recursion guarantee: the SDK's OTLP/HTTP
  exporter uses `package:http` itself, so wrapping an exporter
  call in this helper prevents the export-creates-span-creates-
  export loop. Matches the pattern used by `dartastic_grpc_otel`.
- 10 unit tests covering happy path, header injection, 4xx, 5xx,
  transport exception, userinfo redaction, body size,
  custom span name, parent-span inheritance, and the suppression
  scope. 1 integration test polling an OTLP backend round-trip.
- Targets `http: ^1.0.0`.
