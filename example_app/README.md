# otel_http example app

A standalone runnable demo of `otel_http` exporting telemetry to a
local OTLP-capable backend with a trace UI.

## Run

```sh
# 1. Start any OTLP-compatible backend that also serves a trace UI,
#    exposing ports 3000 (UI), 4317 (OTLP/gRPC) and 4318 (OTLP/HTTP).

# 2. Run the app
cd example_app
dart pub get
dart run bin/main.dart
```

## What it does

Five scenarios, each in its own parent span — together producing
one `run-scenarios` trace with 11 spans (5 scenario parents + 5
client spans + the root):

| Scenario | What it proves |
|---|---|
| `happy-path-get` | 200 → span status stays Ok, full HTTP semconv set |
| `not-found-404` | 4xx → span status flipped to Error |
| `server-error-500` | 5xx → span status flipped to Error |
| `transport-failure` | Bad DNS → `recordException`, `error.type` set, Error status, no `http.response.status_code` |
| `post-with-body` | POST → `http.request.method=POST`, `http.request.body.size` from Content-Length |

## Where to look

In your trace UI (http://localhost:3000 for the container above):

- Service name: `http-otel-example-app`
- Open the `run-scenarios` trace and you'll see all five scenarios
  as child spans, each with their `GET` / `POST` client span
  underneath.
- Click any client span to inspect the HTTP semantic-convention
  attribute set.

## Env

| Variable | Default | Purpose |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | OTLP HTTP endpoint (the SDK's default protocol). For gRPC, also set `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` and point at port 4317. |
