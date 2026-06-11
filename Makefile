.PHONY: all linux-amd64 linux-arm64 windows-amd64 windows-386 darwin-amd64 darwin-arm64 docker clean

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS  := -s -w -X main.version=$(VERSION)
DIST     := dist

all: linux-amd64 linux-arm64 windows-amd64 windows-386 darwin-amd64 darwin-arm64

$(DIST):
	mkdir -p $(DIST)

linux-amd64: $(DIST)
	GOOS=linux   GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo              .

linux-arm64: $(DIST)
	GOOS=linux   GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-arm64        .

windows-amd64: $(DIST)
	GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo.exe          .

windows-386: $(DIST)
	GOOS=windows GOARCH=386   CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-386.exe      .

darwin-amd64: $(DIST)
	GOOS=darwin  GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-darwin-amd64 .

darwin-arm64: $(DIST)
	GOOS=darwin  GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-darwin-arm64 .

docker:
	docker build --build-arg VERSION=$(VERSION) -t goservicedemo:$(VERSION) -t goservicedemo:latest .

clean:
	rm -rf $(DIST)
