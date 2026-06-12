# Builds

Pre-built standalone binaries for SLICE IT! · The Potato Cutting Championship.

**No .NET installation required** — each binary is a self-contained single
file (~35 MB, the .NET runtime is bundled inside). Download the one for your
platform and run it directly.

> Note: only the single file is needed. If an exe ever fails silently on
> double-click, it was built without `dotnet publish -p:PublishSingleFile=true`
> and is missing its runtime DLLs — grab a fresh copy from a release instead.

## Platforms

- **`win-x64/`** — Windows x64 executable (`.exe`)
- **`linux-x64/`** — Linux x64 executable

## Download

For the latest official releases, visit:
https://github.com/angads22/POTATO/releases/latest

Each release includes pre-compiled binaries for Windows and Linux.

## Usage

### Windows
```
PotatoSlicer.exe
```
Double-click or run from PowerShell/Command Prompt.

### Linux
```
chmod +x PotatoSlicer
./PotatoSlicer
```

## Auto-Update

The game checks for updates on launch and can automatically install newer versions from GitHub Releases. You can also manually check via **[6] Check for Updates** in the main menu.

To skip the auto-update check (e.g., if offline), launch with:
```
PotatoSlicer --no-update
```
