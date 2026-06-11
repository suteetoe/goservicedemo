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
