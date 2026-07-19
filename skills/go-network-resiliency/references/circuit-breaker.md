# Circuit breaker — libraries, config, and error classification

This is the detail behind the **Circuit breaker** section of the main skill. The two
things people get wrong — and the reason this file exists — are:

1. **Error classification.** Counting the wrong errors (a 404, a validation error, a
   caller cancellation) as breaker failures trips the breaker on healthy traffic.
2. **The open check.** Detecting "this call was rejected because the breaker is open"
   is not a sentinel-equality check in most libraries; get it wrong and you either
   never see rejections or mislabel real errors as rejections.

## Library options

| Library | Model | Reach for it when |
|---|---|---|
| `github.com/cep21/circuit/v4` | Hystrix-style: rolling error-%, execution timeout, max-concurrency, fallbacks | You want the full toolkit — per-dependency tuning, concurrency limiting, and metrics hooks. This is the example used throughout. |
| `github.com/sony/gobreaker` | Simple count-based state machine (`ReadyToTrip` callback) | You want a small, well-understood breaker and don't need concurrency limits or fallbacks. |
| `github.com/eapache/go-resiliency/breaker` | Minimal: error/success thresholds + timeout | You want the least surface area and a plain `Run(func() error)`. |

The classification principle below applies to all three; only the "how do I exclude an
error" and "how do I detect open" mechanics differ per library.

## Wiring `cep21/circuit`

Configure the opener/closer once as circuit defaults, set per-circuit execution limits
when you create each circuit, and give **each upstream dependency its own circuit** (a
shared breaker conflates unrelated failures).

```go
import (
	"github.com/cep21/circuit/v4"
	"github.com/cep21/circuit/v4/closers/hystrix"
)

manager := circuit.Manager{
	DefaultCircuitProperties: []circuit.CommandPropertiesConstructor{
		hystrix.Factory{
			ConfigureOpener: hystrix.ConfigureOpener{
				// Don't evaluate the error rate until this many requests have
				// happened in the rolling window — otherwise the first failed
				// call (1/1 = 100%) trips the breaker.
				RequestVolumeThreshold: 20,
				// Trip once this % of requests in the window are failures.
				ErrorThresholdPercentage: 50,
			},
			ConfigureCloser: hystrix.ConfigureCloser{
				// After tripping, wait this long before letting a trial request
				// through to test recovery (half-open).
				SleepWindow: 5 * time.Second,
				// Trial successes needed to fully close again.
				RequiredConcurrentSuccessful: 1,
			},
		}.Configure,
	},
}

cb := manager.MustCreateCircuit("payments-api", circuit.Config{
	Execution: circuit.ExecutionConfig{
		Timeout:               1 * time.Second, // per-attempt cap enforced by the breaker
		MaxConcurrentRequests: 100,             // shed load past this (bulkhead)
	},
})
```

Note `Execution.Timeout` overlaps with the outer `context.WithTimeout` from the main
skill's Timeout section — keep the context timeout as the source of truth for the whole
attempt and either leave the breaker timeout looser or omit it, so you don't get two
different deadlines racing.

## Error classification — the crux

The rule: **resiliency failures** (the upstream is unhealthy) count against the breaker;
**business/expected outcomes** (the upstream answered, the answer was "no") do not, and
**caller-side conditions** never do.

```go
// isResiliencyFailure reports whether err means "the upstream is unhealthy" —
// the only kind of error that should count toward opening the breaker.
func isResiliencyFailure(ctx context.Context, err error) bool {
	if err == nil {
		return false
	}
	// Caller walked away or the whole attempt deadline blew — not the upstream's
	// fault. Never count these (and usually don't retry them either).
	if errors.Is(err, context.Canceled) {
		return false
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return true // a per-call timeout IS an upstream-health signal
	}

	// Business/expected errors: the upstream responded correctly with a "no".
	// Adapt these to your client. Examples:
	//   - HTTP 4xx (except 429): not-found, validation, unauthorized, conflict
	//   - gRPC codes: NotFound, InvalidArgument, AlreadyExists, PermissionDenied,
	//     FailedPrecondition, Unauthenticated
	var httpErr *HTTPStatusError
	if errors.As(err, &httpErr) {
		switch {
		case httpErr.Code == 429: // rate limited — upstream IS unhealthy for us
			return true
		case httpErr.Code >= 400 && httpErr.Code < 500:
			return false // expected "no", not a failure
		case httpErr.Code >= 500:
			return true // 5xx, unavailable, bad gateway
		}
	}

	// Transport-level failures (connection refused, reset, DNS, TLS) reach here
	// and default to true: the upstream didn't answer.
	return true
}
```

The gRPC equivalent maps `status.Code(err)`: treat `Unavailable`, `DeadlineExceeded`,
`ResourceExhausted`, `Aborted`, `Internal`, `DataLoss` as failures; treat `NotFound`,
`InvalidArgument`, `AlreadyExists`, `PermissionDenied`, `Unauthenticated`,
`FailedPrecondition`, `OutOfRange` as expected outcomes.

### Two ways to keep a business error from counting

The main skill's example returns `nil` from the run func for expected errors and carries
the real error out through a separate `callErr` variable. That works because "no error
returned" = "not a failure". The cep21-native alternative preserves the error *through*
`Execute` by wrapping it so the breaker ignores it:

```go
err := cb.Execute(ctx, func(ctx context.Context) error {
	resp, upstreamErr := doUpstreamCall(ctx)
	if upstreamErr == nil {
		result = resp
		return nil
	}
	if isResiliencyFailure(ctx, upstreamErr) {
		return upstreamErr // counts against the breaker
	}
	// Expected "no": propagate to the caller WITHOUT counting it.
	return &circuit.SimpleBadRequest{Err: upstreamErr}
}, nil)
```

Then unwrap on the way out: `circuit.IsBadRequest(err)` is true for wrapped business
errors, and `errors.Unwrap(err)`/`errors.As` recovers the original. Pick one style and
keep it consistent — the separate-`callErr` style is simpler to read; the
`SimpleBadRequest` style keeps a single error channel.

## The breaker-open check

When the breaker is open (or the concurrency limit is hit) and there's no fallback,
`Execute`/`Run` returns an error that satisfies the `circuit.Error` interface. **Detect it
with `errors.As`, not equality** — there is no exported sentinel to compare against:

```go
// isCircuitOpen reports whether err is the breaker rejecting the call locally
// (open circuit or concurrency limit) rather than a real upstream error.
func isCircuitOpen(err error) bool {
	var cerr circuit.Error
	return errors.As(err, &cerr) && (cerr.CircuitOpen() || cerr.ConcurrencyLimitReached())
}
```

```go
// circuit.Error, for reference:
type Error interface {
	error
	CircuitOpen() bool             // rejected because the circuit is open
	ConcurrencyLimitReached() bool // rejected because MaxConcurrentRequests was hit
}
```

Distinguish the two if it matters to the caller: an open circuit means "known-bad upstream,
back off"; a concurrency-limit rejection means "we're saturated, shed" — different metrics
tags (see `observability.md`) and sometimes different caller behavior.

For a *proactive* check (e.g. deciding whether to even attempt, or for a health endpoint)
use the state method rather than inspecting an error: `cb.IsOpen() bool`.

## Tuning notes

- **Per dependency, not per process.** One circuit per upstream service (or per critical
  endpoint if one endpoint fails independently). Naming: `MustCreateCircuit("payments-api")`.
- **`RequestVolumeThreshold` guards low traffic.** Without it, a single early failure is
  100% error rate and trips instantly. 20 is the Hystrix default; raise it for chatty
  circuits, lower it for rare-but-critical ones.
- **`SleepWindow` is your recovery probe cadence.** Too short and you hammer a recovering
  upstream; too long and you stay degraded after it's healthy. 5s is a reasonable start.
- **Concurrency limit is a bulkhead.** `MaxConcurrentRequests` caps in-flight calls so a
  slow upstream can't exhaust your goroutines/connections even before the breaker opens.
