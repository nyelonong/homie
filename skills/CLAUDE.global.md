<!-- homie:baseline-golang — appended to ~/.claude/CLAUDE.md by ~/homie/bootstrap.sh; edit here -->
## Golang — always use the `golang-*` skills

When writing, reviewing, debugging, or setting up **Go** code in ANY project, invoke
the relevant `golang-*` skills (the samber/cc-skills-golang pack, in `~/.claude/skills/`)
before and while touching Go. More than one usually applies; when in doubt, invoke it.

- **Start with `golang-how-to`** — the orchestrator: it reads the task and loads the
  right skills (a gRPC service → `golang-grpc` + `golang-testing` + `golang-error-handling`;
  a panic → `golang-troubleshooting` + `golang-safety`; a security audit →
  `golang-security` + `golang-lint` + `golang-safety`).
- For Go that makes **outbound network calls** (HTTP/gRPC clients, upstream APIs, DBs),
  also use **`go-network-resiliency`** — a bespoke skill (not in the samber pack, so
  `golang-how-to` won't route to it) covering the six pillars (timeout, circuit breaker,
  cache, singleflight, observability, retry) and their composition order.
- Process skills (e.g. `systematic-debugging`) still come first; the `golang-*` skills
  are the Go implementation layer.
- A project's own `CLAUDE.md` / `AGENTS.md` takes precedence where it conflicts.
