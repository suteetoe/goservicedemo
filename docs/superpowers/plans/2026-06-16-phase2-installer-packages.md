# Go Service Demo — Phase 2: Native Installer Packages (Windows + macOS)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create native installer packages — a `.pkg` for macOS and an `.msi` for Windows — that install the service binary and register it as a system service automatically on first boot.

**Architecture:** macOS uses `pkgbuild` to assemble a flat component package with a launchd plist payload and pre/postinstall scripts; the `.pkg` is built locally on the macOS dev machine. Windows uses WiX v4 (via `dotnet tool install --global wix`) to produce an MSI that registers the binary as a Windows Service; MSI building runs on Windows (CI via GitHub Actions). Both are triggered by `make package-macos-{arm64,amd64}` and `make package-windows` Makefile targets. A GitHub Actions workflow on tag push builds and attaches both artifacts to a GitHub release.

**Tech Stack:** `pkgbuild` + `productbuild` (macOS built-in), WiX Toolset v4 (dotnet), GNU Make, GitHub Actions

---

## File Map

| Path | Action | Responsibility |
|---|---|---|
| `docs/superpowers/specs/2026-06-11-go-service-design.md` | Modify | Rename Phase 2→3 (Tray App); add Phase 2 section (installer packages) |
| `build/macos/com.goservicedemo.plist` | Create | launchd LaunchDaemon plist (runs service at boot as root) |
| `build/macos/scripts/preinstall` | Create | Stops running service before upgrade (no-op on fresh install) |
| `build/macos/scripts/postinstall` | Create | Bootstraps the launchd service after files are installed |
| `build/windows/goservicedemo.wxs` | Create | WiX v4 installer definition: binary + ServiceInstall + ServiceControl |
| `Makefile` | Modify | Add `package-macos-arm64`, `package-macos-amd64`, `package-windows` targets |
| `.github/workflows/release.yml` | Create | On `v*` tag: build + package on macOS + Windows runners, attach to GitHub release |

---

## Task 1: Update Spec — Reorganize Phases

**Files:**
- Modify: `docs/superpowers/specs/2026-06-11-go-service-design.md`

- [ ] **Step 1: Rename current Phase 2 heading and add new Phase 2 section**

Open `docs/superpowers/specs/2026-06-11-go-service-design.md`.

Replace:

```markdown
## 14. Phase 2 — System Tray Status App (deferred)
```

With:

```markdown
## 14. Phase 2 — Native Installer Packages (Windows + macOS)

Produce a `.pkg` installer for macOS and an `.msi` installer for Windows that install `goservicedemo` to standard system paths and register it as a service that starts automatically on boot.

**macOS `.pkg`:**
- Payload: binary → `/usr/local/bin/goservicedemo`; launchd plist → `/Library/LaunchDaemons/com.goservicedemo.plist`
- `preinstall` script: `launchctl bootout system /Library/LaunchDaemons/com.goservicedemo.plist` (idempotent on fresh install)
- `postinstall` script: `launchctl bootstrap system /Library/LaunchDaemons/com.goservicedemo.plist`
- Built with `pkgbuild` (macOS built-in). Separate packages for `arm64` and `amd64`.

**Windows `.msi`:**
- Installs `goservicedemo.exe` to `%ProgramFiles%\Go Service Demo\`
- Registers as a Windows Service (SCM) via WiX `ServiceInstall` + `ServiceControl` elements
- Service starts automatically on install; stops and is removed on uninstall
- Built with WiX Toolset v4 (`wix build`) — requires Windows or a Windows CI runner

**Makefile targets:** `make package-macos-arm64`, `make package-macos-amd64`, `make package-windows`

**CI:** GitHub Actions workflow on `v*` tag builds both artifacts and attaches them to a GitHub Release.

---

## 15. Phase 3 — System Tray Status App (deferred)
```

- [ ] **Step 2: Verify the spec renders cleanly**

```bash
grep -n "Phase" docs/superpowers/specs/2026-06-11-go-service-design.md
```

Expected output contains both `Phase 2` and `Phase 3` headings.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-06-11-go-service-design.md
git commit -m "docs: reorganize phases — Phase 2 installer packages, Phase 3 tray app"
```

---

## Task 2: macOS — launchd Plist and Install Scripts

**Files:**
- Create: `build/macos/com.goservicedemo.plist`
- Create: `build/macos/scripts/preinstall`
- Create: `build/macos/scripts/postinstall`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p build/macos/scripts
```

- [ ] **Step 2: Create the launchd plist**

Create `build/macos/com.goservicedemo.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.goservicedemo</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/goservicedemo</string>
        <string>-port</string>
        <string>8080</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/goservicedemo/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/goservicedemo/stderr.log</string>
</dict>
</plist>
```

- [ ] **Step 3: Create the preinstall script**

Create `build/macos/scripts/preinstall`:

```bash
#!/bin/bash
set -e
PLIST=/Library/LaunchDaemons/com.goservicedemo.plist
if [ -f "$PLIST" ]; then
    launchctl bootout system "$PLIST" 2>/dev/null || true
fi
```

```bash
chmod +x build/macos/scripts/preinstall
```

- [ ] **Step 4: Create the postinstall script**

Create `build/macos/scripts/postinstall`:

```bash
#!/bin/bash
set -e
mkdir -p /var/log/goservicedemo
launchctl bootstrap system /Library/LaunchDaemons/com.goservicedemo.plist
```

```bash
chmod +x build/macos/scripts/postinstall
```

- [ ] **Step 5: Validate script syntax**

```bash
bash -n build/macos/scripts/preinstall && echo "preinstall OK"
bash -n build/macos/scripts/postinstall && echo "postinstall OK"
```

Expected:
```
preinstall OK
postinstall OK
```

- [ ] **Step 6: Commit**

```bash
git add build/macos/
git commit -m "feat: add macOS launchd plist and pkg install scripts"
```

---

## Task 3: macOS — Makefile Targets and Local Build Test

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add the packaging targets to Makefile**

Open `Makefile`. After the `darwin-arm64` target, add the following block:

```makefile
# macOS pkg (requires macOS — pkgbuild is not available on Linux/Windows)
PKG_STAGING := $(DIST)/pkg-staging
PKG_VERSION  = $(VERSION:v%=%)

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
```

Also update the `.PHONY` line at the top to include the new targets:

```makefile
.PHONY: all linux-amd64 linux-arm64 windows-amd64 windows-386 darwin-amd64 darwin-arm64 \
        package-macos-arm64 package-macos-amd64 package-windows docker clean
```

- [ ] **Step 2: Build the arm64 package locally**

```bash
make package-macos-arm64
```

Expected: `dist/goservicedemo-dev-macos-arm64.pkg` (or tagged version) is created with no errors.

```bash
ls -lh dist/*.pkg
```

Expected: file exists, size in the range of 1–10 MB.

- [ ] **Step 3: Inspect the package contents**

```bash
pkgutil --payload-files dist/goservicedemo-dev-macos-arm64.pkg
```

Expected output contains:
```
.
./Library
./Library/LaunchDaemons
./Library/LaunchDaemons/com.goservicedemo.plist
./usr
./usr/local
./usr/local/bin
./usr/local/bin/goservicedemo
```

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add macOS pkg Makefile targets (package-macos-arm64, package-macos-amd64)"
```

---

## Task 4: Windows — WiX Installer Definition

**Files:**
- Create: `build/windows/goservicedemo.wxs`

- [ ] **Step 1: Create directory**

```bash
mkdir -p build/windows
```

- [ ] **Step 2: Create the WiX v4 installer definition**

Create `build/windows/goservicedemo.wxs`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">

  <Package Name="Go Service Demo"
           Manufacturer="goservicedemo"
           Version="$(var.Version)"
           UpgradeCode="7E8F9A0B-1C2D-3E4F-5A6B-7C8D9E0F1A2B">

    <MajorUpgrade DowngradeErrorMessage="A newer version of Go Service Demo is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <StandardDirectory Id="ProgramFilesFolder">
      <Directory Id="INSTALLFOLDER" Name="Go Service Demo" />
    </StandardDirectory>

    <ComponentGroup Id="ProductComponents" Directory="INSTALLFOLDER">
      <Component Guid="*">
        <File Source="$(var.DistDir)\goservicedemo.exe" KeyPath="yes" />
        <ServiceInstall Id="GoServiceDemoInstall"
                        Name="goservicedemo"
                        DisplayName="Go Service Demo"
                        Description="A demo Go RESTful web service (HTTP CRUD, health endpoint)"
                        Start="auto"
                        Type="ownProcess"
                        ErrorControl="normal"
                        Arguments="-port 8080" />
        <ServiceControl Id="GoServiceDemoControl"
                        Name="goservicedemo"
                        Start="install"
                        Stop="both"
                        Remove="uninstall"
                        Wait="yes" />
      </Component>
    </ComponentGroup>

    <Feature Id="MainFeature" Title="Go Service Demo" Level="1">
      <ComponentGroupRef Id="ProductComponents" />
    </Feature>

  </Package>
</Wix>
```

- [ ] **Step 3: Commit**

```bash
git add build/windows/goservicedemo.wxs
git commit -m "feat: add WiX v4 MSI installer definition for Windows"
```

---

## Task 5: Windows — Makefile Target

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add Windows packaging target**

In `Makefile`, after the `package-macos-amd64` block, add:

```makefile
# Windows MSI (requires Windows with WiX v4: dotnet tool install --global wix)
package-windows: windows-amd64
	wix build build/windows/goservicedemo.wxs \
	  -d DistDir=$(DIST) \
	  -d Version=$(PKG_VERSION) \
	  -o $(DIST)/goservicedemo-$(VERSION)-windows-amd64.msi
```

- [ ] **Step 2: Verify the Makefile parses without errors**

```bash
make --dry-run package-windows 2>&1 | head -5
```

Expected: shows the `wix build` command (with unresolved `$(DIST)` and `$(VERSION)` filled in), no syntax errors.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add Windows MSI Makefile target (package-windows, requires WiX v4 on Windows)"
```

---

## Task 6: GitHub Actions Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the workflows directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  package-macos:
    runs-on: macos-latest
    strategy:
      matrix:
        include:
          - arch: arm64
            goarch: arm64
          - arch: amd64
            goarch: amd64
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'

      - name: Build darwin binary
        run: |
          GOOS=darwin GOARCH=${{ matrix.goarch }} CGO_ENABLED=0 \
          go build \
            -ldflags="-s -w -X main.version=${{ github.ref_name }}" \
            -o dist/goservicedemo-darwin-${{ matrix.goarch }} .

      - name: Build .pkg
        run: make package-macos-${{ matrix.arch }} VERSION=${{ github.ref_name }}

      - uses: actions/upload-artifact@v4
        with:
          name: pkg-macos-${{ matrix.arch }}
          path: dist/*.pkg

  package-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'

      - name: Install WiX v4
        run: dotnet tool install --global wix

      - name: Build binary and MSI
        shell: bash
        run: |
          GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
          go build \
            -ldflags="-s -w -X main.version=${{ github.ref_name }}" \
            -o dist/goservicedemo.exe .
          VER="${{ github.ref_name }}"
          PKG_VERSION="${VER#v}"
          wix build build/windows/goservicedemo.wxs \
            -d DistDir=dist \
            -d Version="$PKG_VERSION" \
            -o "dist/goservicedemo-${{ github.ref_name }}-windows-amd64.msi"

      - uses: actions/upload-artifact@v4
        with:
          name: msi-windows-amd64
          path: dist/*.msi

  release:
    needs: [package-macos, package-windows]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: List artifacts
        run: ls -lh artifacts/

      - uses: softprops/action-gh-release@v2
        with:
          files: artifacts/*
          generate_release_notes: true
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add GitHub Actions release workflow — macOS pkg + Windows MSI on tag push"
```

---

## Self-Review

**Spec coverage:**
- ✅ macOS .pkg with launchd: Tasks 2 + 3
- ✅ Windows MSI with SCM registration: Tasks 4 + 5
- ✅ Makefile targets for both platforms: Tasks 3 + 5
- ✅ CI workflow on tag push: Task 6
- ✅ Phase reorganization in spec: Task 1

**Placeholder scan:** No TBD, TODO, or "similar to" references found.

**Type consistency:** No types shared across tasks — each task is file-level configuration or shell commands.

**Version handling note:** `pkgbuild` requires a numeric version (`1.0.0`), not a `v`-prefixed tag (`v1.0.0`). The Makefile handles this with `PKG_VERSION = $(VERSION:v%=%)`. The GitHub Actions Windows step strips the prefix with `VER="${VER#v}"`.
