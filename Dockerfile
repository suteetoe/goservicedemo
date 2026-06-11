# ---- Stage 1: Build ----
FROM golang:1.25-alpine AS builder

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
