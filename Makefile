.PHONY: all linux-amd64 linux-arm64 windows-amd64 windows-386 darwin-amd64 darwin-arm64 \
        package-macos-arm64 package-macos-amd64 package-windows docker clean

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

# Note: darwin binaries link against system frameworks (libSystem, libresolv) even with
# CGO_ENABLED=0 — this is macOS linker behavior, not a CGO dependency. They work on any macOS.
darwin-amd64: $(DIST)
	GOOS=darwin  GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-darwin-amd64 .

darwin-arm64: $(DIST)
	GOOS=darwin  GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o $(DIST)/goservicedemo-darwin-arm64 .

# macOS pkg (requires macOS — pkgbuild is not available on Linux/Windows)
PKG_STAGING := $(DIST)/pkg-staging
PKG_VERSION  = $(shell echo "$(VERSION)" | sed 's/^v//' | sed 's/[^0-9.].*/.0/' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$$' || echo "0.0.1")

package-macos-arm64: darwin-arm64
	@mkdir -p $(PKG_STAGING)/usr/local/bin $(PKG_STAGING)/Library/LaunchDaemons
	cp $(DIST)/goservicedemo-darwin-arm64 $(PKG_STAGING)/usr/local/bin/goservicedemo
	cp build/macos/com.goservicedemo.plist $(PKG_STAGING)/Library/LaunchDaemons/
	pkgbuild \
	  --root $(PKG_STAGING) \
	  --scripts build/macos/scripts \
	  --identifier com.goservicedemo \
	  --version $(PKG_VERSION) \
	  --install-location / \
	  $(DIST)/goservicedemo-$(VERSION)-macos-arm64.pkg
	@rm -rf $(PKG_STAGING)

package-macos-amd64: darwin-amd64
	@mkdir -p $(PKG_STAGING)/usr/local/bin $(PKG_STAGING)/Library/LaunchDaemons
	cp $(DIST)/goservicedemo-darwin-amd64 $(PKG_STAGING)/usr/local/bin/goservicedemo
	cp build/macos/com.goservicedemo.plist $(PKG_STAGING)/Library/LaunchDaemons/
	pkgbuild \
	  --root $(PKG_STAGING) \
	  --scripts build/macos/scripts \
	  --identifier com.goservicedemo \
	  --version $(PKG_VERSION) \
	  --install-location / \
	  $(DIST)/goservicedemo-$(VERSION)-macos-amd64.pkg
	@rm -rf $(PKG_STAGING)

# Windows MSI (requires Windows with WiX v4: dotnet tool install --global wix)
package-windows: windows-amd64
	wix build build/windows/goservicedemo.wxs \
	  -d DistDir=$(DIST) \
	  -d Version=$(PKG_VERSION) \
	  -o $(DIST)/goservicedemo-$(VERSION)-windows-amd64.msi

docker:
	docker build --build-arg VERSION=$(VERSION) -t goservicedemo:$(VERSION) -t goservicedemo:latest .

clean:
	rm -rf $(DIST)
