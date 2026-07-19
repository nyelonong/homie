---
name: go-network-resiliency
description: Patterns for making outbound network calls resilient in Go — HTTP/gRPC clients, wrappers around external APIs, databases, or any upstream dependency. Covers the six resiliency pillars — timeout, circuit breaker, cache, singleflight, observability, and retry — and, critically, the order they should be composed in. Use this skill whenever writing, scaffolding, or refactoring Go code that calls out to another service, even if the user doesn't say "resiliency," "circuit breaker," or "timeout" explicitly — phrases like "wrap this HTTP call," "handle upstream failures," "the API is flaky," "add retry logic," "prevent duplicate calls," "cut down load on X service," or "instrument this client with metrics" are all strong signals. Also use when reviewing existing Go network-call code for missing timeout/circuit-breaker/retry handling.
---

# Go Network Call Resiliency

Captured internal best practice for making Go code that calls external services (HTTP APIs, gRPC services, databases — anything over the network) resilient to slowness and failure. This assumes there's **no service mesh** doing the work for you; if there is one (Istio, Linkerd, etc.), it typically already covers timeout, circuit breaking, retry, and load balancing at the infrastructure layer, and duplicating that logic in application code is usually redundant. Ask if you're unsure.

## The six pillars

1. **Timeout** — bound how long you'll wait for a single call.
2. **Circuit breaker** — stop calling an upstream that's clearly failing, so you don't pile on load it can't handle and don't tie up your own resources waiting on it.
3. **Cache** — avoid making the call at all when a recent result is already known.
4. **Singleflight** — collapse concurrent identical in-flight requests into one.
5. **Observability** — measure rate, errors, and duration (RED) so failures are visible before they page someone.
6. **Retry** — try again on transient failure, within a budget.

Reach for whichever subset the situation actually calls for — not every call needs all six. A low-volume, non-critical internal call might only need a timeout. A high-traffic call to a flaky third-party payment API on the critical path probably wants most of the list.

## Composition order matters

These aren't independent add-ons; layered in the wrong order they interact badly. The order that works, from outermost to innermost:

```
retry
  → singleflight-dedup + cache-check
      → circuit breaker
          → timeout-bound call to the real function
```

Why this order, not some other:

- **Retry goes on the outside.** If retry were wrapped *inside* the circuit breaker or cache layer, only the first attempt would benefit from those protections — a naive inner retry loop can hammer a struggling upstream with 3x the traffic and blow past what the circuit breaker was there to prevent. Wrapping the whole stack in retry means every attempt gets the full benefit of the timeout, breaker, and cache logic.
- **Cache is checked before the circuit breaker gate.** A cache hit should return instantly regardless of breaker state — there's no reason to fail a cacheable read just because the breaker happens to be open.
- **Singleflight sits between cache-miss and the breaker/call.** Once you know you need to go to the actual upstream, dedupe concurrent identical requests before they all separately trip through the breaker and timeout logic.
- **Timeout is innermost**, scoped tightly to the actual call, so it doesn't get diluted by time spent in cache lookups or breaker bookkeeping.

Don't build a single "God wrapper" that hardcodes this for every call site (a `Magic` struct that always does all six regardless of need adds indirection without matching the situation — build the layers that this specific call needs). But when a call site does need more than one or two of these, write a small local helper for that call site combining exactly the layers it needs, in this order.

## Timeout

Use `context.WithTimeout`, propagate the context all the way into the actual network call (the underlying HTTP/gRPC client must respect `ctx`, or the timeout does nothing), and distinguish deadline-exceeded from caller-cancellation — they usually need different handling upstream.

```go
ctx, cancel := context.WithTimeout(ctx, timeoutDuration)
defer cancel()

resp, err := doUpstreamCall(ctx) // must actually honor ctx internally
if err != nil {
	switch {
	case errors.Is(ctx.Err(), context.DeadlineExceeded):
		// this call timed out — usually a resiliency concern (retry/CB candidate)
	case errors.Is(ctx.Err(), context.Canceled):
		// caller walked away — usually not a resiliency failure, don't retry/count it
	default:
		// some other error from the call itself
	}
}
```

## Circuit breaker

See `references/circuit-breaker.md` for library choices, full config, wiring, and — most importantly — how to classify which errors should and shouldn't count as breaker failures (this is the part people get wrong most often: a 404 or a validation error is not the same kind of failure as a 503, and counting it as one will trip the breaker on healthy traffic).

Minimal shape of the wiring, using `cep21/circuit`'s hystrix-style breaker as the example (any breaker library follows the same shape — a lambda around the real call that returns an error the breaker counts). Two things people typically miss on a first draft, both shown below: the closure's return value is what the breaker counts, but it is *not* how you get your actual data (or a business error) back to the caller — the breaker's bookkeeping and the caller's result are two separate concerns, tracked through two separate outer variables, not conflated into the one `error` the closure returns. There's also no `ErrCircuitOpen`-style sentinel to check later — see the reference for the real API.

```go
var (
	result  *Response // what the caller gets back on success
	callErr error     // what the caller gets back on failure — NOT necessarily what the breaker saw
)

err := cb.Execute(ctx, func(ctx context.Context) error {
	resp, upstreamErr := doUpstreamCall(ctx)
	callErr = upstreamErr // always propagate to the caller, regardless of breaker accounting
	if isResiliencyFailure(ctx, upstreamErr) {
		return upstreamErr // counts against the breaker
	}
	result = resp
	return nil // business/expected error, or success — doesn't count against the breaker,
	           // but callErr above still carries it back to the caller
}, nil)

if isCircuitOpen(err) {
	return nil, err // breaker rejected locally, no real callErr to report
}
return result, callErr
```

(`isResiliencyFailure` and `isCircuitOpen` are defined in `references/circuit-breaker.md` — don't guess at their shape, the classification logic and the breaker-open check are both easy to get subtly wrong.)

## Cache

Define a small interface so the concrete library (ristretto, go-cache, otter, ccache, ...) is swappable — this space moves fast and you don't want every call site coupled to one library's API.

```go
type Cache interface {
	Get(ctx context.Context, key string) (any, bool)
	Set(ctx context.Context, key string, val any) error
}
```

Build the key from the call's arguments, check before calling, populate on success only:

```go
key := cacheKey(args...)
if val, ok := cache.Get(ctx, key); ok {
	return val, nil
}
val, err := doUpstreamCall(ctx, args...)
if err == nil {
	_ = cache.Set(ctx, key, val)
}
return val, err
```

Only cache calls whose staleness is acceptable for the use case — don't reach for this reflexively.

## Singleflight

`golang.org/x/sync/singleflight` collapses concurrent calls sharing the same key into one in-flight call; all callers get the same result (or error). Useful under traffic spikes where many callers ask for the same thing (e.g. the same user profile) within a short window.

```go
var sf singleflight.Group

val, err, _ := sf.Do(key, func() (any, error) {
	return doUpstreamCall(ctx, args...)
})
```

Caveat: if the shared result is a pointer/mutable value, every caller shares the same object — make sure downstream code doesn't mutate it, or return a copy.

## Observability

RED (Rate, Error, Duration) is the minimum bar: a request counter and a latency histogram, tagged with enough attributes (source/dest service, endpoint, method, use case, and — importantly — *why* a call failed: timed out vs. breaker-open vs. concurrency-limited vs. upstream error vs. cache hit) to actually debug from. See `references/observability.md` for full OpenTelemetry wiring and the attribute/result taxonomy.

Record duration from immediately before the real call to immediately after — don't let cache hits or breaker-open short-circuits get counted as if they were full-latency calls, but do count them (tagged differently) so cache hit rate and breaker-open rate are visible.

## Retry

Retry goes at the outermost layer (see "Composition order" above) so every attempt gets the full benefit of timeout, cache, breaker, and singleflight. Before adding retry, check two things:

- **Is the call idempotent?** Retrying a non-idempotent call (e.g. "charge this card," "create this record") can duplicate side effects. Either confirm idempotency, use an idempotency key the upstream supports, or don't retry that call — surface the failure instead.
- **What's the retry budget?** Bound retries by both attempt count *and* the overall deadline (the parent context's timeout), so a chain of retries can't quietly turn a 500ms call into a 10s one. Prefer exponential backoff with jitter over fixed-interval retry, so a fleet of clients retrying in sync doesn't create a thundering herd against an already-struggling upstream.

```go
const baseBackoff = 50 * time.Millisecond

func withRetry(ctx context.Context, maxAttempts int, fn func(context.Context) error) error {
	var err error
	backoff := baseBackoff
	for attempt := 0; attempt < maxAttempts; attempt++ {
		if err = fn(ctx); err == nil || !isRetryable(err) {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(backoff + jitter(backoff)):
			backoff *= 2
		}
	}
	return err
}

// jitter returns a random duration in [0, d/2) so that many callers retrying
// on the same schedule don't all wake up and hit the upstream at once.
func jitter(d time.Duration) time.Duration {
	return time.Duration(rand.Int63n(int64(d)/2 + 1))
}
```

`fn` here is the *entire* timeout+cache+breaker+singleflight stack for one attempt — not just the bare network call.

## Checklist when writing or reviewing a resilient call

- Does the context ever get to the actual client (HTTP transport / gRPC dial), or is the timeout decorative?
- Are business/expected errors (4xx, validation, not-found) kept separate from resiliency errors (5xx, timeout, connection refused) in whatever's deciding breaker state and retry eligibility?
- If retry exists, does it wrap the *whole* per-attempt stack, and is it bounded by both attempts and deadline?
- If a call is retried, is it actually safe to repeat (idempotent, or protected by an idempotency key)?
- Do the metrics distinguish cache hits, breaker-open rejections, and real upstream errors — or does everything collapse into one generic "error" bucket that's useless for on-call debugging?
- Is this solving a real problem for this call site, or importing a `Magic`-style everything-wrapper out of habit for a call that only needed a timeout?

## References

- `references/circuit-breaker.md` — library options (cep21/circuit, sony/gobreaker, eapache/go-resiliency), full config parameters explained, and error-classification patterns.
- `references/observability.md` — OpenTelemetry RED-metrics wiring, attribute taxonomy, and result classification (cache hit / breaker open / concurrency limited / upstream error).
