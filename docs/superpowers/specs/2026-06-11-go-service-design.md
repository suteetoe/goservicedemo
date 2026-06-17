# Go Service Demo — Design Spec

**Date:** 2026-06-11  
**Status:** Approved  

---

## 1. Goal

Produce a production-ready Go RESTful web service whose compiled binary can run in five distinct deployment modes without recompilation:

1. Standalone foreground process
2. Windows Service (via SCM)
3. Ubuntu systemd service
4. macOS service (via launchd)
5. Docker container

---

## 2. Project Layout

```
goservicedemo/
├── main.go                  — entry point: flag parsing, service lifecycle wiring
├── Dockerfile               — multi-stage build (builder → scratch final image)
├── go.mod
├── go.sum
└── internal/
    ├── config/
    │   └── config.go        — Config struct; CLI flags with env var overrides
    ├── store/
    │   └── store.go         — thread-safe in-memory Item store (sync.RWMutex + map)
    ├── api/
    │   ├── router.go        — chi router setup, middleware chain, route mounting
    │   └── handlers.go      — HTTP handler funcs for /health and /api/items CRUD
    └── svc/
        └── service.go       — kardianos/service Program interface implementation
```

**Dependency flow (no import cycles):**

```
main → svc → api → store
         ↓       ↓
       config  config
```

---

## 3. Dependencies

| Package | Version | Purpose |
|---|---|---|
| `github.com/go-chi/chi/v5` | latest | HTTP router + middleware |
| `github.com/kardianos/service` | latest | Cross-platform service lifecycle |
| `github.com/google/uuid` | latest | UUID v4 generation for item IDs |

Go standard library handles: `net/http`, `log/slog`, `sync`, `context`, `os/signal`.

---

## 4. Configuration

Priority: **CLI flag → environment variable → hardcoded default**

| CLI Flag | Env Var | Default | Description |
|---|---|---|---|
| `-port` | `PORT` | `8080` | HTTP listen port |
| `-name` | `SERVICE_NAME` | `goservicedemo` | OS service registration name |
| `-display` | `SERVICE_DISPLAY` | `Go Service Demo` | Windows SCM display name |
| `-description` | `SERVICE_DESC` | `Go RESTful service demo` | Service description string |
| `-log-level` | `LOG_LEVEL` | `info` | Logging level: debug/info/warn/error |

Config is parsed once in `main.go` and passed by value to all packages that need it.

---

## 5. API Contract

### 5.1 Health

| Method | Path | Response |
|---|---|---|
| `GET` | `/health` | `200 {"status":"ok","version":"<build_version>","uptime":"<duration>"}` — version defaults to `"dev"` unless injected via `-ldflags "-X main.version=..."` at build time |

### 5.2 Items CRUD

**Item schema:**
```json
{
  "id":          "string (UUID v4, auto-generated)",
  "name":        "string (required on POST/PUT)",
  "description": "string (optional)",
  "created_at":  "string (RFC3339, auto-set on POST)"
}
```

| Method | Path | Success | Error conditions |
|---|---|---|---|
| `GET` | `/api/items` | `200` JSON array (empty `[]` if none) | — |
| `POST` | `/api/items` | `201` created item | `400` malformed JSON or missing `name` |
| `GET` | `/api/items/{id}` | `200` item | `404` not found |
| `PUT` | `/api/items/{id}` | `200` updated item | `400` bad body / `404` not found |
| `DELETE` | `/api/items/{id}` | `204 No Content` | `404` not found |

All error responses use a consistent envelope:
```json
{"error": "human-readable message"}
```

### 5.3 Middleware Chain (applied in order)

1. `chi/middleware.RequestID` — injects `X-Request-ID` into request context and response header
2. `chi/middleware.RealIP` — respects `X-Forwarded-For` / `X-Real-IP` headers
3. Custom slog request logger — structured JSON: `method`, `path`, `status`, `latency_ms`, `request_id`, `remote_addr`
4. `chi/middleware.Recoverer` — catches panics, logs stack trace, returns `500`

---

## 6. Service Lifecycle (`internal/svc`)

The `Program` struct implements `kardianos/service.Interface`:

```go
type Program struct {
    cfg    config.Config
    server *http.Server
    cancel context.CancelFunc
}

func (p *Program) Start(s service.Service) error  // non-blocking: starts HTTP server in goroutine
func (p *Program) Stop(s service.Service) error   // graceful: 5s shutdown timeout via context
```

**Startup sequence in `main.go`:**
1. Parse `config.Config` from flags + env
2. Set `slog` global logger (level from config)
3. Construct `store.Store`
4. Construct `api.Router` (passing store)
5. Construct `http.Server`
6. Construct `svc.Program`
7. Build `kardianos/service.Config` and call `service.New(program, svcConfig)`
8. Dispatch `-service <action>` flag if present, else call `s.Run()`

**Graceful shutdown:** `Stop()` calls `httpServer.Shutdown(ctx)` with a 5-second context timeout. In-flight requests drain; new connections are refused.

**Signal handling in foreground mode:** When running without a service manager (direct execution), `kardianos/service` still calls `Start`/`Stop` correctly. `SIGINT`/`SIGTERM` trigger `Stop`.

---

## 7. In-Memory Store (`internal/store`)

```go
type Item struct {
    ID          string    `json:"id"`
    Name        string    `json:"name"`
    Description string    `json:"description"`
    CreatedAt   time.Time `json:"created_at"`
}

type Store struct {
    mu    sync.RWMutex
    items map[string]Item
}
```

Methods: `List() []Item`, `Get(id) (Item, bool)`, `Create(name, description) Item`, `Update(id, name, description) (Item, bool)`, `Delete(id) bool`.

`sync.RWMutex` allows concurrent reads; writes are exclusively locked.

---

## 8. Logging

Uses Go 1.21+ `log/slog` with `slog.NewJSONHandler`. Log level is set globally from config. All handler funcs receive the logger via the `api` package (injected at construction time). The middleware request logger also uses `slog`.

Example log line:
```json
{"time":"2026-06-11T10:00:00Z","level":"INFO","msg":"request","method":"GET","path":"/api/items","status":200,"latency_ms":1,"request_id":"abc123"}
```

---

## 9. Dockerfile

**Multi-stage build:**

- **Stage 1 — builder** (`golang:1.23-alpine`):
  - Sets `CGO_ENABLED=0`, `GOOS=linux`, `GOARCH=amd64`
  - Strips debug info: `-ldflags="-s -w"`
  - Injects build-time version: `-ldflags="-X main.version=$(git describe)"`
  - Copies `go.mod`/`go.sum` first to leverage layer cache

- **Stage 2 — final** (`scratch`):
  - Copies binary only
  - Copies `/etc/ssl/certs/ca-certificates.crt` from builder (for HTTPS outbound calls)
  - `EXPOSE 8080`
  - Entrypoint: `["/goservicedemo"]`

Expected final image size: **~5–8 MB**.

---

## 10. Cross-Compilation Targets

| OS | Arch | Output binary | Notes |
|---|---|---|---|
| linux | amd64 | `goservicedemo` | Primary; matches Docker image |
| linux | arm64 | `goservicedemo-arm64` | ARM servers (Graviton, RPi 4) |
| windows | amd64 | `goservicedemo.exe` | Modern 64-bit Windows |
| windows | 386 | `goservicedemo-386.exe` | Legacy 32-bit Windows; SCM path limit: 256 chars |
| darwin | amd64 | `goservicedemo-darwin-amd64` | macOS Intel |
| darwin | arm64 | `goservicedemo-darwin-arm64` | macOS Apple Silicon (M-series) |

Build script (`Makefile` or shell loop) iterates these six targets. All builds use `CGO_ENABLED=0`.

**Windows/386 note:** The Windows SCM has a 256-character limit on the registered binary path. Install the service from a short path (e.g., `C:\svc\goservicedemo-386.exe`) to avoid truncation.

---

## 11. Deployment Instructions Summary

### 11.1 Build

```bash
# Linux amd64
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o goservicedemo .

# Linux arm64
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -o goservicedemo-arm64 .

# Windows amd64
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o goservicedemo.exe .

# Windows 386 (legacy)
GOOS=windows GOARCH=386 CGO_ENABLED=0 go build -ldflags="-s -w" -o goservicedemo-386.exe .

# macOS Intel
GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o goservicedemo-darwin-amd64 .

# macOS Apple Silicon
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -o goservicedemo-darwin-arm64 .
```

### 11.2 Windows Service

```powershell
# Run as Administrator
.\goservicedemo.exe -service install
.\goservicedemo.exe -service start
# Stop and uninstall
.\goservicedemo.exe -service stop
.\goservicedemo.exe -service uninstall
```

### 11.3 Ubuntu systemd

```bash
# kardianos/service generates and installs the unit file automatically
sudo ./goservicedemo -service install
sudo systemctl start goservicedemo
sudo systemctl enable goservicedemo
sudo systemctl status goservicedemo
# Logs
journalctl -u goservicedemo -f
```

### 11.4 macOS launchd

```bash
# kardianos/service generates and installs the launchd plist automatically
# (~/.config/launchd/<name>.plist for user agent, or /Library/LaunchDaemons/ for system daemon)
sudo ./goservicedemo-darwin-arm64 -service install
sudo ./goservicedemo-darwin-arm64 -service start
# Stop and uninstall
sudo ./goservicedemo-darwin-arm64 -service stop
sudo ./goservicedemo-darwin-arm64 -service uninstall
# View logs via Console.app or:
log stream --predicate 'subsystem == "goservicedemo"' --level debug
```

### 11.5 Docker

```bash
docker build -t goservicedemo:latest .
docker run -d -p 8080:8080 --name goservicedemo goservicedemo:latest
# With env var config
docker run -d -p 9090:9090 -e PORT=9090 -e LOG_LEVEL=debug goservicedemo:latest
```

### 11.6 Standalone (foreground)

```bash
./goservicedemo -port 8080 -log-level debug
# Ctrl+C for graceful shutdown
```

---

## 12. Error Handling Strategy

- **Validation errors (400):** Missing required fields, malformed JSON body
- **Not found (404):** Item ID does not exist in store
- **Internal errors (500):** Unexpected panics (caught by Recoverer middleware); all 500s log a stack trace via slog
- **No silent failures:** All errors are logged at appropriate level before the response is written
- **No custom error types** at this scope — plain `error` returns with descriptive strings

---

## 13. Testing Approach

Not in scope for initial implementation (the service is a reference/demo). The store's methods and handler logic are designed to be easily unit-tested in isolation (store has no external dependencies; handlers take `http.ResponseWriter`/`*http.Request`).

---

## 14. Phase 2 — System Tray Status App (deferred)

A separate binary (`goservicedemotray`) that displays the service status in the OS taskbar/menu bar.

**Platforms:** Windows (taskbar notification area) + macOS (menu bar).

**Mechanism:** Polls the service's `GET /health` endpoint every 5 seconds. Displays a colored icon (green = running, red = stopped/unreachable) and a right-click context menu with:
- Service name + current status
- Start / Stop / Restart actions (shells out to `sc.exe` on Windows, `launchctl` on macOS)
- Open in Browser (opens `http://localhost:<port>` in default browser)
- Quit tray app

**Key library:** `fyne.io/systray` (maintained fork of `getlantern/systray`). Requires `CGO_ENABLED=1` — built separately from the service binary.

**Packaging (bundled with installer):**
- **Windows:** MSI installer bundles both `goservicedemo.exe` and `goservicedemotray.exe`. Tray app added to startup via registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- **macOS:** `.pkg` installer bundles both binaries. Tray app added as a Login Item via launchd user agent plist.

**Note:** `.deb` packaging applies to Linux (Ubuntu), not macOS. macOS native packaging is `.pkg` or `.dmg`.
