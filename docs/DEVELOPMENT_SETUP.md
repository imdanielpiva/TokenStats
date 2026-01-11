# Development Setup Guide

## Reducing Keychain Permission Prompts

When developing TokenStats, you may see frequent keychain permission prompts like:

> **TokenStats wants to access key "Claude Code-credentials" in your keychain.**

This happens because each rebuild creates a new code signature, and macOS treats it as a "different" app.

### Quick Fix (Temporary)

When the prompt appears, click **"Always Allow"** instead of just "Allow". This grants access to the current build.

### Permanent Fix (Recommended)

Use a stable development certificate that doesn't change between rebuilds:

#### 1. Create Development Certificate

```bash
./Scripts/setup_dev_signing.sh
```

This creates a self-signed certificate named "TokenStats Development".

#### 2. Trust the Certificate

1. Open **Keychain Access.app**
2. Find **"TokenStats Development"** in the **login** keychain
3. Double-click it
4. Expand the **"Trust"** section
5. Set **"Code Signing"** to **"Always Trust"**
6. Close the window (enter your password when prompted)

#### 3. Configure Your Shell

Add this to your `~/.zshrc` (or `~/.bashrc` if using bash):

```bash
export APP_IDENTITY='TokenStats Development'
```

Then restart your terminal:

```bash
source ~/.zshrc
```

#### 4. Rebuild

```bash
./Scripts/compile_and_run.sh
```

Now your builds will use the stable certificate, and keychain prompts will be much less frequent!

---

## Cleaning Up Old App Bundles

If you see multiple `TokenStats *.app` bundles in your project directory, you can clean them up:

```bash
# Remove all numbered builds
rm -rf "TokenStats "*.app

# The .gitignore already excludes these patterns:
# - TokenStats.app
# - TokenStats *.app/
```

The build script creates `TokenStats.app` in the project root. Old numbered builds (like `TokenStats 2.app`) are created when Finder can't overwrite the running app.

---

## Development Workflow

### Standard Build & Run

```bash
./Scripts/compile_and_run.sh
```

This script:
1. Kills existing TokenStats instances
2. Runs `swift build` (release mode)
3. Runs `swift test` (all tests)
4. Packages the app with `./Scripts/package_app.sh`
5. Launches `TokenStats.app`
6. Verifies it stays running

### Quick Build (No Tests)

```bash
swift build -c release
./Scripts/package_app.sh
```

### Run Tests Only

```bash
swift test
```

### Debug Build

```bash
swift build  # defaults to debug
./Scripts/package_app.sh debug
```

---

## Troubleshooting

### "TokenStats is already running"

The compile_and_run script should kill old instances, but if it doesn't:

```bash
pkill -x TokenStats || pkill -f TokenStats.app || true
```

### "Permission denied" when accessing keychain

Make sure you clicked **"Always Allow"** or set up the development certificate (see above).

### Multiple app bundles keep appearing

This happens when the running app locks the bundle. The compile_and_run script handles this by killing the app first.

If you still see old bundles:

```bash
rm -rf "TokenStats "*.app
```

### App doesn't reflect latest changes

Always rebuild and restart:

```bash
./Scripts/compile_and_run.sh
```

Or manually:

```bash
./Scripts/package_app.sh
pkill -x TokenStats || pkill -f TokenStats.app || true
open -n TokenStats.app
```

