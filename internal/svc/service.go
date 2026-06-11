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
