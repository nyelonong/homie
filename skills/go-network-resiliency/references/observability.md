# Observability — RED metrics wiring and the result taxonomy

This is the detail behind the **Observability** section of the main skill. The bar is
RED — **R**ate, **E**rrors, **D**uration — with enough attributes to answer "what kind of
failure?" without opening a trace. The part people skip is the **result classification**:
if timeouts, breaker-open rejections, cache hits, and real upstream errors all collapse
into one generic "error", the metrics are useless on call.

## Instruments (OpenTelemetry Go)

Three instruments cover RED for an outbound call: a request counter (rate + errors, split
by the `result` attribute), a duration histogram, and an in-flight up/down counter.

```go
import (
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

type clientMetrics struct {
	requests metric.Int64Counter
	duration metric.Float64Histogram
	inflight metric.Int64UpDownCounter
}

func newClientMetrics() (*clientMetrics, error) {
	m := otel.Meter("myapp/upstream") // uses the globally-configured MeterProvider

	requests, err := m.Int64Counter("upstream.client.requests",
		metric.WithDescription("Outbound upstream calls, tagged by result"),
		metric.WithUnit("{request}"))
	if err != nil {
		return nil, err
	}
	duration, err := m.Float64Histogram("upstream.client.duration",
		metric.WithDescription("Outbound upstream call latency"),
		metric.WithUnit("s"),
		// Explicit buckets tuned to your SLO beat the defaults for latency.
		metric.WithExplicitBucketBoundaries(
			0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10))
	if err != nil {
		return nil, err
	}
	inflight, err := m.Int64UpDownCounter("upstream.client.inflight",
		metric.WithDescription("In-flight outbound upstream calls"),
		metric.WithUnit("{request}"))
	if err != nil {
		return nil, err
	}
	return &clientMetrics{requests, duration, inflight}, nil
}
```

Record **duration in seconds** (`elapsed.Seconds()`) — that's the OTel convention and lets
backends compare across services.

## The attribute taxonomy

Every measurement carries the same base attributes so you can slice by any of them. Prefer
the OTel semantic-convention keys (`go.opentelemetry.io/otel/semconv/...`) where one exists:

| Attribute | Example | Purpose |
|---|---|---|
| `peer.service` / `server.address` | `payments-api` | which upstream |
| `service.name` | `checkout` | which caller (usually set on the Resource, not per-metric) |
| `rpc.method` / `http.request.method` | `Charge` / `POST` | operation |
| `http.route` / endpoint | `/v1/charges` | operation detail — **the templated route, never the raw path with IDs** |
| `use_case` | `checkout.authorize` | your business context; the most useful custom tag |
| `result` | `timeout` | **the failure taxonomy — see below** |

**Cardinality is the trap.** Every distinct attribute-value combination is a separate time
series. Never tag with unbounded values — user IDs, raw URLs with path params, full error
strings, request IDs. Use the templated route, a bounded `result` enum, and a bounded
`use_case`. When in doubt, put the high-cardinality detail on a *trace span*, not a metric.

## The result taxonomy

A bounded set of outcomes, aligned with the circuit-breaker classification
(`circuit-breaker.md`) so the two references agree:

```go
const (
	resultOK            = "ok"                  // success
	resultBadRequest    = "bad_request"         // expected business "no" (4xx, NotFound, …)
	resultTimeout       = "timeout"             // context deadline exceeded on the call
	resultCanceled      = "canceled"            // caller walked away (context.Canceled)
	resultUpstreamError = "upstream_error"      // 5xx, connection refused, unavailable
	resultCircuitOpen   = "circuit_open"        // breaker rejected locally
	resultConcurrency   = "concurrency_limited" // bulkhead / MaxConcurrentRequests
	resultCacheHit      = "cache_hit"           // served from cache, no call made
)

func classify(ctx context.Context, err error) string {
	switch {
	case err == nil:
		return resultOK
	case isCircuitOpen(err): // from circuit-breaker.md — check BEFORE generic errors
		return resultCircuitOpen
	case errors.Is(err, context.Canceled):
		return resultCanceled
	case errors.Is(err, context.DeadlineExceeded):
		return resultTimeout
	case !isResiliencyFailure(ctx, err): // expected business error
		return resultBadRequest
	default:
		return resultUpstreamError
	}
}
```

`concurrency_limited` and `cache_hit` come from where they're known (the breaker's
`ConcurrencyLimitReached()` and the cache-hit branch), not from `classify`, because those
paths don't produce an upstream error to inspect.

## Recording around the stack

Record the counter for **every** outcome (including cache hits and breaker-open rejections
— that's how cache-hit rate and breaker-open rate become visible). Record **duration only
around the real call**, so a cache hit or an instant breaker rejection doesn't pollute the
latency histogram with fake-fast (or fake-slow) samples.

```go
func (c *clientMetrics) observe(ctx context.Context, base []attribute.KeyValue,
	result string, callStart time.Time, madeRealCall bool) {

	attrs := append(base, attribute.String("result", result))
	set := metric.WithAttributes(attrs...)

	c.requests.Add(ctx, 1, set)
	if madeRealCall {
		c.duration.Record(ctx, time.Since(callStart).Seconds(), set)
	}
}
```

Wiring it into the resiliency layers (mirrors the composition order in the main skill):

```go
base := []attribute.KeyValue{
	attribute.String("peer.service", "payments-api"),
	attribute.String("use_case", "checkout.authorize"),
	attribute.String("rpc.method", "Charge"),
}

// cache hit: count it, no duration, no real call
if v, ok := cache.Get(ctx, key); ok {
	metrics.observe(ctx, base, resultCacheHit, time.Time{}, false)
	return v, nil
}

metrics.inflight.Add(ctx, 1, metric.WithAttributes(base...))
start := time.Now()
resp, err := cb.Execute(ctx, realCall, nil)
metrics.inflight.Add(ctx, -1, metric.WithAttributes(base...))

metrics.observe(ctx, base, classify(ctx, err), start, /*madeRealCall=*/ !isCircuitOpen(err))
```

Note the `madeRealCall` guard: a breaker-open rejection never reached the upstream, so it's
excluded from the duration histogram but still counted (as `circuit_open`) in the request
counter.

## Traces and exemplars

Metrics tell you *that* p99 spiked and which `result` dominates; traces tell you *why* a
specific call was slow. Wrap the real call in a span
(`tracer.Start(ctx, "upstream.charge")`), set the same base attributes plus the
high-cardinality detail (request ID, full target) that must **not** go on metrics, and set
the span status from the same `classify` result. If your metrics pipeline supports
**exemplars**, they'll link a histogram bucket sample straight to the trace that produced
it — the fastest path from "p99 is bad" to "here's a slow trace".
