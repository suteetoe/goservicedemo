# Go Service Demo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a production-ready Go RESTful web service that runs as a standalone process, Windows Service, Ubuntu systemd service, macOS launchd service, and Docker container — from a single binary.

**Architecture:** Flat `internal/` sub-packages (`config`, `store`, `api`, `svc`) wired together in `main.go`. The `kardianos/service` package provides cross-platform service lifecycle management; `chi` handles HTTP routing with structured `slog` middleware. No CGO, no shared state between packages, no import cycles.

**Tech Stack:** Go 1.23, `github.com/go-chi/chi/v5`, `github.com/kardianos/service`, `github.com/google/uuid`, Go stdlib `log/slog`, `net/http`, `sync`

---

## File Map

| Path | Action | Responsibility |
|---|---|---|
| `go.mod` | Create | Module definition (`goservicedemo`) |
| `go.sum` | Auto-generated | Dependency checksums |
| `main.go` | Create | Entry point: parse config, wire deps, run service |
| `internal/config/config.go` | Create | `Config` struct; CLI flags + env var overrides |
| `internal/store/store.go` | Create | Thread-safe in-memory `Item` store |
| `internal/api/handlers.go` | Create | HTTP handler funcs (`health`, CRUD) |
| `internal/api/router.go` | Create | chi router, middleware chain, `NewRouter` constructor |
| `internal/svc/service.go` | Create | `Program` struct implementing `kardianos/service.Interface` |
| `Dockerfile` | Create | Multi-stage build: `golang:1.23-alpine` → `scratch` |
| `Makefile` | Create | Cross-compilation targets for 6 OS/arch combos |

---

## Task 1: Initialize Go Module and Fetch Dependencies

**Files:**
- Create: `go.mod`
- Create: `main.go` (stub — replaced in Task 7)

- [x] **Step 1: Create the project directory structure**

```bash
cd /Users/toe/DEV/goservicedemo
mkdir -p internal/config internal/store internal/api internal/svc dist
```

- [x] **Step 2: Initialize the Go module**

```bash
go mod init goservicedemo
```

Expected output:
```
go: creating new go.mod: module goservicedemo
```

- [x] **Step 3: Create a stub `main.go` (required for `go mod tidy`)**

Create `main.go` with this content:

```go
package main

func main() {}
```

- [x] **Step 4: Fetch all three dependencies**

```bash
go get github.com/go-chi/chi/v5@latest
go get github.com/kardianos/service@latest
go get github.com/google/uuid@latest
```

Each command prints the resolved version (e.g., `go: added github.com/go-chi/chi/v5 v5.x.x`).

- [x] **Step 5: Tidy and verify**

```bash
go mod tidy
go build ./...
```

Expected: no errors, no output. `go.sum` is generated.

- [x] **Step 6: Commit**

```bash
git init
git add go.mod go.sum main.go
git commit -m "chore: initialize go module with dependencies"
```

---

## Task 2: Implement `internal/config/config.go`

**Files:**
- Create: `internal/config/config.go`

- [x] **Step 1: Create the file**

Create `internal/config/config.go`:

```go
package config

import (
	"flag"
	"log/slog"
	"os"
	"strconv"
)

type Config struct {
	Port           int
	ServiceName    string
	ServiceDisplay string
	ServiceDesc    string
	LogLevel       slog.Level
	ServiceAction  string
}

func Load() Config {
	port := flag.Int("port", 8080, "HTTP listen port")
	name := flag.String("name", "goservicedemo", "OS service registration name")
	display := flag.String("display", "Go Service Demo", "Windows SCM display name")
	desc := flag.String("description", "Go RESTful service demo", "Service description")
	logLevel := flag.String("log-level", "info", "Log level: debug, info, warn, error")
	svcAction := flag.String("service", "", "Service action: install, start, stop, uninstall")
	flag.Parse()

	if v := os.Getenv("PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			*port = n
		}
	}
	if v := os.Getenv("SERVICE_NAME"); v != "" {
		*name = v
	}
	if v := os.Getenv("SERVICE_DISPLAY"); v != "" {
		*display = v
	}
	if v := os.Getenv("SERVICE_DESC"); v != "" {
		*desc = v
	}
	if v := os.Getenv("LOG_LEVEL"); v != "" {
		*logLevel = v
	}

	var level slog.Level
	switch *logLevel {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}

	return Config{
		Port:           *port,
		ServiceName:    *name,
		ServiceDisplay: *display,
		ServiceDesc:    *desc,
		LogLevel:       level,
		ServiceAction:  *svcAction,
	}
}
```

- [x] **Step 2: Verify it compiles**

```bash
go build ./internal/config/...
```

Expected: no output, no errors.

- [x] **Step 3: Commit**

```bash
git add internal/config/config.go
git commit -m "feat: add config package with flag and env var parsing"
```

---

## Task 3: Implement `internal/store/store.go`

**Files:**
- Create: `internal/store/store.go`

- [x] **Step 1: Create the file**

Create `internal/store/store.go`:

```go
package store

import (
	"sync"
	"time"

	"github.com/google/uuid"
)

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

func New() *Store {
	return &Store{items: make(map[string]Item)}
}

func (s *Store) List() []Item {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]Item, 0, len(s.items))
	for _, item := range s.items {
		result = append(result, item)
	}
	return result
}

func (s *Store) Get(id string) (Item, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	item, ok := s.items[id]
	return item, ok
}

func (s *Store) Create(name, description string) Item {
	item := Item{
		ID:          uuid.NewString(),
		Name:        name,
		Description: description,
		CreatedAt:   time.Now().UTC(),
	}
	s.mu.Lock()
	s.items[item.ID] = item
	s.mu.Unlock()
	return item
}

func (s *Store) Update(id, name, description string) (Item, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	item, ok := s.items[id]
	if !ok {
		return Item{}, false
	}
	item.Name = name
	item.Description = description
	s.items[id] = item
	return item, true
}

func (s *Store) Delete(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.items[id]
	if ok {
		delete(s.items, id)
	}
	return ok
}
```

- [x] **Step 2: Verify it compiles**

```bash
go build ./internal/store/...
```

Expected: no output, no errors.

- [x] **Step 3: Commit**

```bash
git add internal/store/store.go
git commit -m "feat: add thread-safe in-memory item store"
```

---

## Task 4: Implement `internal/api/handlers.go`

**Files:**
- Create: `internal/api/handlers.go`

- [x] **Step 1: Create the file**

Create `internal/api/handlers.go`:

```go
package api

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"goservicedemo/internal/store"
)

type handlers struct {
	store     *store.Store
	version   string
	startTime time.Time
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func (h *handlers) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"version": h.version,
		"uptime":  time.Since(h.startTime).Round(time.Second).String(),
	})
}

func (h *handlers) listItems(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.store.List())
}

func (h *handlers) createItem(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "malformed JSON body")
		return
	}
	if body.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	writeJSON(w, http.StatusCreated, h.store.Create(body.Name, body.Description))
}

func (h *handlers) getItem(w http.ResponseWriter, r *http.Request) {
	item, ok := h.store.Get(chi.URLParam(r, "id"))
	if !ok {
		writeError(w, http.StatusNotFound, "item not found")
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *handlers) updateItem(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "malformed JSON body")
		return
	}
	if body.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	item, ok := h.store.Update(chi.URLParam(r, "id"), body.Name, body.Description)
	if !ok {
		writeError(w, http.StatusNotFound, "item not found")
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *handlers) deleteItem(w http.ResponseWriter, r *http.Request) {
	if !h.store.Delete(chi.URLParam(r, "id")) {
		writeError(w, http.StatusNotFound, "item not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
```

- [x] **Step 2: Stage the file (do NOT verify compile yet — router.go is needed to complete the package)**

```bash
git add internal/api/handlers.go
```

---

## Task 5: Implement `internal/api/router.go`

**Files:**
- Create: `internal/api/router.go`

- [x] **Step 1: Create the file**

Create `internal/api/router.go`:

```go
package api

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"goservicedemo/internal/store"
)

func NewRouter(s *store.Store, logger *slog.Logger, version string) http.Handler {
	h := &handlers{
		store:     s,
		version:   version,
		startTime: time.Now(),
	}

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(requestLogger(logger))
	r.Use(middleware.Recoverer)

	r.Get("/health", h.health)
	r.Route("/api/items", func(r chi.Router) {
		r.Get("/", h.listItems)
		r.Post("/", h.createItem)
		r.Get("/{id}", h.getItem)
		r.Put("/{id}", h.updateItem)
		r.Delete("/{id}", h.deleteItem)
	})

	return r
}

func requestLogger(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			start := time.Now()
			next.ServeHTTP(ww, r)
			logger.Info("request",
				"method", r.Method,
				"path", r.URL.Path,
				"status", ww.Status(),
				"latency_ms", time.Since(start).Milliseconds(),
				"request_id", middleware.GetReqID(r.Context()),
				"remote_addr", r.RemoteAddr,
			)
		})
	}
}
```

- [x] **Step 2: Verify the api package compiles**

```bash
go build ./internal/api/...
```

Expected: no output, no errors.

- [x] **Step 3: Commit both api files**

```bash
git add internal/api/router.go
git commit -m "feat: add api package with chi router, middleware, and CRUD handlers"
```

---

## Task 6: Implement `internal/svc/service.go`

**Files:**
- Create: `internal/svc/service.go`

- [x] **Step 1: Create the file**

Create `internal/svc/service.go`:

```go
package svc

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/kardianos/service"
)

// Program implements service.Interface for kardianos/service.
// Start is non-blocking (spawns goroutine); Stop performs a 5-second graceful shutdown.
type Program struct {
	server *http.Server
	logger *slog.Logger
}

func New(server *http.Server, logger *slog.Logger) *Program {
	return &Program{server: server, logger: logger}
}

func (p *Program) Start(_ service.Service) error {
	go func() {
		p.logger.Info("HTTP server starting", "addr", p.server.Addr)
		if err := p.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			p.logger.Error("HTTP server error", "error", err)
		}
	}()
	return nil
}

func (p *Program) Stop(_ service.Service) error {
	p.logger.Info("shutting down HTTP server")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := p.server.Shutdown(ctx); err != nil {
		return fmt.Errorf("server shutdown: %w", err)
	}
	return nil
}
```

- [x] **Step 2: Verify it compiles**

```bash
go build ./internal/svc/...
```

Expected: no output, no errors.

- [x] **Step 3: Commit**

```bash
git add internal/svc/service.go
git commit -m "feat: add svc package wrapping kardianos/service lifecycle"
```

---

## Task 7: Implement `main.go`

**Files:**
- Modify: `main.go` (replaces the stub from Task 1)

- [x] **Step 1: Replace stub `main.go` with the full implementation**

Overwrite `main.go` with:

```go
package main

import (
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/kardianos/service"
	"goservicedemo/internal/api"
	"goservicedemo/internal/config"
	"goservicedemo/internal/store"
	"goservicedemo/internal/svc"
)

// version is injected at build time via:
//   -ldflags "-X main.version=<tag>"
// Defaults to "dev" for local builds.
var version = "dev"

func main() {
	cfg := config.Load()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: cfg.LogLevel,
	}))
	slog.SetDefault(logger)

	itemStore := store.New()
	router := api.NewRouter(itemStore, logger, version)

	server := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Port),
		Handler:      router,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	program := svc.New(server, logger)

	svcConfig := &service.Config{
		Name:        cfg.ServiceName,
		DisplayName: cfg.ServiceDisplay,
		Description: cfg.ServiceDesc,
	}

	s, err := service.New(program, svcConfig)
	if err != nil {
		logger.Error("failed to create service", "error", err)
		os.Exit(1)
	}

	if cfg.ServiceAction != "" {
		if err := service.Control(s, cfg.ServiceAction); err != nil {
			logger.Error("service control failed", "action", cfg.ServiceAction, "error", err)
			os.Exit(1)
		}
		return
	}

	if err := s.Run(); err != nil {
		logger.Error("service run failed", "error", err)
		os.Exit(1)
	}
}
```

- [x] **Step 2: Verify the entire project compiles**

```bash
go build ./...
```

Expected: no output, no errors. (`./...` compiles all packages but discards binaries — use the next command to produce the runnable binary.)

```bash
go build .
```

Expected: produces `goservicedemo` (macOS/Linux) or `goservicedemo.exe` (Windows) in the current directory.

- [x] **Step 3: Commit**

```bash
git add main.go
git commit -m "feat: implement main.go wiring config, store, api, and service lifecycle"
```

---

## Task 8: Local Smoke Test

**Files:** None — verification only.

- [x] **Step 1: Start the service in foreground mode (in one terminal)**

```bash
go run . -port 8080 -log-level debug
```

Expected log output (JSON):
```json
{"time":"...","level":"INFO","msg":"HTTP server starting","addr":":8080"}
```

Leave this running. Open a second terminal for the next steps.

- [x] **Step 2: Verify the health endpoint**

```bash
curl -s http://localhost:8080/health | jq .
```

Expected:
```json
{
  "status": "ok",
  "uptime": "0s",
  "version": "dev"
}
```

- [x] **Step 3: Create an item**

```bash
curl -s -X POST http://localhost:8080/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"Widget A","description":"First test item"}' | jq .
```

Expected (note the `id` — copy it for later steps):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Widget A",
  "description": "First test item",
  "created_at": "2026-06-11T..."
}
```

- [x] **Step 4: List items**

```bash
curl -s http://localhost:8080/api/items | jq .
```

Expected: JSON array containing the item created above.

- [x] **Step 5: Get a single item (replace `<id>` with the UUID from Step 3)**

```bash
curl -s http://localhost:8080/api/items/<id> | jq .
```

Expected: the same item object.

- [x] **Step 6: Update the item**

```bash
curl -s -X PUT http://localhost:8080/api/items/<id> \
  -H "Content-Type: application/json" \
  -d '{"name":"Widget A v2","description":"Updated"}' | jq .
```

Expected: item returned with `"name": "Widget A v2"`.

- [x] **Step 7: Verify 400 on missing name**

```bash
curl -s -X POST http://localhost:8080/api/items \
  -H "Content-Type: application/json" \
  -d '{"description":"no name here"}' | jq .
```

Expected:
```json
{"error": "name is required"}
```

- [x] **Step 8: Delete the item**

```bash
curl -s -o /dev/null -w "%{http_code}" -X DELETE http://localhost:8080/api/items/<id>
```

Expected: `204`

- [x] **Step 9: Verify 404 after delete**

```bash
curl -s http://localhost:8080/api/items/<id> | jq .
```

Expected:
```json
{"error": "item not found"}
```

- [x] **Step 10: Stop the server**

Press `Ctrl+C` in the first terminal.

Expected log output:
```json
{"time":"...","level":"INFO","msg":"shutting down HTTP server"}
```

No errors. Clean exit.

---

## Task 9: Write Dockerfile

**Files:**
- Create: `Dockerfile`

- [x] **Step 1: Create the Dockerfile**

Create `Dockerfile`:

```dockerfile
# ---- Stage 1: Build ----
FROM golang:1.23-alpine AS builder

# Install CA certs so we can copy them to the scratch image
RUN apk add --no-cache ca-certificates

WORKDIR /build

# Copy dependency files first — Docker caches this layer separately.
# Only re-downloaded when go.mod or go.sum changes.
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -ldflags="-s -w -X main.version=${VERSION}" \
    -o goservicedemo .

# ---- Stage 2: Final (scratch = zero OS overhead, ~5-8 MB total) ----
FROM scratch

# Required for any HTTPS outbound requests from the service
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /build/goservicedemo /goservicedemo

EXPOSE 8080

ENTRYPOINT ["/goservicedemo"]
```

- [x] **Step 2: Build the Docker image**

```bash
docker build -t goservicedemo:latest .
```

Expected: Build completes successfully. Note the final image size in the output (look for `writing image` or run `docker images goservicedemo` afterward — target is under 15 MB).

```bash
docker images goservicedemo
```

Expected output example:
```
REPOSITORY      TAG       IMAGE ID       CREATED          SIZE
goservicedemo   latest    abc123def456   10 seconds ago   7.5MB
```

- [x] **Step 3: Run the container**

```bash
docker run -d -p 8080:8080 --name goservicedemo-test goservicedemo:latest
```

- [x] **Step 4: Verify health inside Docker**

```bash
curl -s http://localhost:8080/health | jq .
```

Expected:
```json
{"status":"ok","uptime":"1s","version":"dev"}
```

- [x] **Step 5: Verify env var config override works**

```bash
docker run --rm -p 9090:9090 -e PORT=9090 -e LOG_LEVEL=debug goservicedemo:latest &
sleep 1
curl -s http://localhost:9090/health | jq .
kill %1
```

Expected: health response on port 9090.

- [x] **Step 6: Stop and remove the test container**

```bash
docker stop goservicedemo-test && docker rm goservicedemo-test
```

- [x] **Step 7: Commit**

```bash
git add Dockerfile
git commit -m "feat: add multi-stage Dockerfile targeting scratch final image"
```

---

## Task 10: Write Makefile for Cross-Compilation

**Files:**
- Create: `Makefile`

**Important:** Makefile recipe lines MUST be indented with a real tab character (`\t`), not spaces.

- [x] **Step 1: Create the Makefile**

Create `Makefile` with tab-indented recipe lines (shown here with `→` representing a tab):

```makefile
.PHONY: all linux-amd64 linux-arm64 windows-amd64 windows-386 darwin-amd64 darwin-arm64 docker clean

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS  := -s -w -X main.version=$(VERSION)
DIST     := dist

all: linux-amd64 linux-arm64 windows-amd64 windows-386 darwin-amd64 darwin-arm64

$(DIST):
→	mkdir -p $(DIST)

linux-amd64: $(DIST)
→	GOOS=linux   GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo              .

linux-arm64: $(DIST)
→	GOOS=linux   GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-arm64        .

windows-amd64: $(DIST)
→	GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo.exe          .

windows-386: $(DIST)
→	GOOS=windows GOARCH=386   CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-386.exe      .

darwin-amd64: $(DIST)
→	GOOS=darwin  GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-darwin-amd64 .

darwin-arm64: $(DIST)
→	GOOS=darwin  GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-darwin-arm64 .

docker:
→	docker build --build-arg VERSION=$(VERSION) -t goservicedemo:$(VERSION) -t goservicedemo:latest .

clean:
→	rm -rf $(DIST)
```

- [x] **Step 2: Build the native macOS binary via make (quick sanity check)**

```bash
make darwin-arm64
```

Expected:
```
GOOS=darwin  GOARCH=arm64 CGO_ENABLED=0 go build ...
```

No errors. `dist/goservicedemo-darwin-arm64` is created.

- [x] **Step 3: Build all cross-compilation targets**

```bash
make all
```

Expected: six binaries produced in `dist/`:

```bash
ls -lh dist/
```

Expected output:
```
-rwxr-xr-x  goservicedemo               (linux/amd64  ~7 MB)
-rwxr-xr-x  goservicedemo-arm64         (linux/arm64  ~7 MB)
-rwxr-xr-x  goservicedemo.exe           (windows/amd64 ~8 MB)
-rwxr-xr-x  goservicedemo-386.exe       (windows/386  ~7 MB)
-rwxr-xr-x  goservicedemo-darwin-amd64  (darwin/amd64 ~7 MB)
-rwxr-xr-x  goservicedemo-darwin-arm64  (darwin/arm64 ~7 MB)
```

- [x] **Step 4: Verify the linux binary is a valid ELF executable**

```bash
file dist/goservicedemo
```

Expected:
```
dist/goservicedemo: ELF 64-bit LSB executable, x86-64, statically linked, ...
```

- [x] **Step 5: Verify the Windows binary header**

```bash
file dist/goservicedemo.exe
```

Expected:
```
dist/goservicedemo.exe: PE32+ executable (console) x86-64 ...
```

- [x] **Step 6: Verify the 386 Windows binary**

```bash
file dist/goservicedemo-386.exe
```

Expected:
```
dist/goservicedemo-386.exe: PE32 executable (console) Intel 80386 ...
```

- [x] **Step 7: Add dist/ to .gitignore and commit**

```bash
echo "dist/" >> .gitignore
git add Makefile .gitignore
git commit -m "feat: add Makefile with cross-compilation targets for 6 OS/arch combos"
```

---

## Deployment Reference (not implementation tasks — for documentation)

### Windows Service (run as Administrator)

```powershell
# Install and start
.\dist\goservicedemo.exe -service install
.\dist\goservicedemo.exe -service start

# Verify status
Get-Service -Name "goservicedemo"
sc query goservicedemo

# Stop and uninstall
.\dist\goservicedemo.exe -service stop
.\dist\goservicedemo.exe -service uninstall
```

**Windows/386 note:** Install from a short path to stay under the 256-char SCM limit:
```powershell
copy dist\goservicedemo-386.exe C:\svc\goservicedemo.exe
C:\svc\goservicedemo.exe -service install
```

### Ubuntu systemd

```bash
sudo cp dist/goservicedemo /usr/local/bin/
sudo /usr/local/bin/goservicedemo -service install
sudo systemctl start goservicedemo
sudo systemctl enable goservicedemo

# Verify
sudo systemctl status goservicedemo
journalctl -u goservicedemo -f

# Uninstall
sudo systemctl stop goservicedemo
sudo /usr/local/bin/goservicedemo -service uninstall
```

### macOS launchd

```bash
sudo cp dist/goservicedemo-darwin-arm64 /usr/local/bin/goservicedemo
sudo /usr/local/bin/goservicedemo -service install
sudo /usr/local/bin/goservicedemo -service start

# Verify (non-zero PID = running)
sudo launchctl list goservicedemo
ps aux | grep goservicedemo

# View logs
log stream --predicate 'subsystem == "goservicedemo"' --level debug

# Uninstall
sudo /usr/local/bin/goservicedemo -service stop
sudo /usr/local/bin/goservicedemo -service uninstall
```

### Docker

```bash
# Build with version tag
make docker

# Run
docker run -d -p 8080:8080 --name goservicedemo goservicedemo:latest

# With configuration overrides
docker run -d -p 9090:9090 \
  -e PORT=9090 \
  -e LOG_LEVEL=debug \
  --name goservicedemo \
  goservicedemo:latest

# Verify
curl -s http://localhost:8080/health | jq .

# Stop
docker stop goservicedemo && docker rm goservicedemo
```
