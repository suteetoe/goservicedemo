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
