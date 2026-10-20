# Topaz Gigapixel on an external drive "is damaged and can't be opened" on macOS — fix without reinstalling

Topaz Gigapixel worked fine, then one day macOS says:

> "Topaz Gigapixel AI" is damaged and can't be opened. You should move it to the Trash.

Clicking **Open Anyway** in System Settings › Privacy & Security doesn't help: the app never shows up. This fix gets it running again in a minute, keeps your downloaded models (13 GB here), and needs no installer.

> **Setup where this happened:** Gigapixel installed on an **external SSD** (`/Volumes/<Drive>/Applications`) to save space on the internal disk. That is not the recommended setup: the installer targets `/Applications` on the internal disk. An external volume gets unmounted, remounted or restored, and each time macOS may drop its cached signature check, which is what triggers the "damaged" error below. An install on the internal disk can hit the same broken seal (e.g. after a macOS update), but less often.

## Why it happens

1. **Gigapixel writes its downloaded AI models inside its own app bundle** (`Contents/Resources/models/`) and also modifies `Contents/Resources/lrtemplates/external editor.lrtemplate`. Any change inside a signed bundle breaks its code seal:

   ```
   $ codesign --verify --deep --strict -v "Topaz Gigapixel AI.app"
   a sealed resource is missing or invalid
   ```

2. macOS checks the signature at first launch, then caches the result. When that cache goes away (volume restored or remounted, macOS update…), Gatekeeper checks again, finds the broken seal and reports the app as "damaged". Here it happened twice, with the app on an external SSD.

3. **Why "Open Anyway" hangs.** `syspolicyd` shows the prompt and then never records the answer. Every later launch waits on that pending evaluation, and the kernel keeps the process suspended before it runs a single instruction:

   ```
   $ log show --last 10m --info --debug --predicate 'process == "syspolicyd"' | grep -i -E 'prompt|evaluation'
   Prompt shown (1, 0x1), waiting for response: PST: (path: …)
   waiting on another evaluation: PST: (path: …)

   $ vmmap --summary <pid>
   Process exists but has not started -- it is launched-suspended
   ```

   The process exists (`pgrep` finds it), but it stays at 32 KB of memory and 0 % CPU.

## Fix

Clone the app to a new name, re-sign the clone ad hoc, and open it. The clone has new inodes, so macOS runs a fresh evaluation instead of waiting on the stuck one.

```bash
curl -O https://raw.githubusercontent.com/Microburo/topaz-gigapixel-damaged-fix/main/fix-damaged-app.sh
chmod +x fix-damaged-app.sh
./fix-damaged-app.sh "/Applications/Topaz Gigapixel AI.app" "Topaz Gigapixel AI 8.4.4"
```

Or by hand:

```bash
pkill -x "Topaz Gigapixel AI"          # kill the suspended process, if any
cp -Rc "/Applications/Topaz Gigapixel AI.app" "/Applications/Topaz Gigapixel AI 2.app"
codesign --force --deep --sign - "/Applications/Topaz Gigapixel AI 2.app"
codesign --verify --deep --strict "/Applications/Topaz Gigapixel AI 2.app"
open "/Applications/Topaz Gigapixel AI 2.app"
```

`cp -c` makes an APFS clone: instant, no extra disk space. The first launch takes ~15 s (XProtect scan). Once the clone works, delete the original. Preferences are tied to the bundle ID, not the path, so the clone keeps them.

Replace `/Applications` with your actual location (e.g. `/Volumes/<Drive>/Applications`).

### Alternative (untested)

Restart `syspolicyd` to drop the stuck evaluation, or simply reboot:

```bash
sudo launchctl kickstart -k system/com.apple.security.syspolicy
```

The original's seal is still broken after that, so you need the `codesign --force --deep --sign -` step anyway.

## Keep it working

- Every new model download writes into the bundle again and breaks the seal. Before moving the app or updating macOS, re-sign it: `codesign --force --deep --sign - "<app>"`.
- Each re-sign changes the code hash: macOS may ask again for access to removable volumes. The app freezes until you click **Allow**.

## Caveats

- The ad hoc signature drops Topaz's Developer ID and entitlements. Upscaling works, but if a plug-in (Photoshop, Lightroom, Capture One) or the in-app updater misbehaves, reinstall with the official installer.
- Plug-ins may look for the app under its original name. Rename the clone back once the original is deleted, if needed.

## What doesn't work

| Attempt | Result |
|---|---|
| Re-sign the original in place | `codesign --verify` passes, launch still suspended (stuck evaluation) |
| Rename the app (`mv`) | Same stuck evaluation |
| Launch the executable directly from Terminal | Same: suspended, 32 KB |
| Restart `CoreServicesUIAgent` | No effect |
| Remove quarantine (`xattr -dr com.apple.quarantine`) | Nothing to remove: no quarantine attribute |
| Move models out of the bundle + symlink | Breaks the seal too (`file added` / `invalid destination for symbolic link in bundle`) |
| `ModelDir` preference | Ignored: the models path is hard-coded to `Contents/Resources/models` on macOS |

## Tested on

- Topaz Gigapixel AI 8.4.4
- macOS 27.0.1, Apple Silicon (M4 Pro)
- App installed on an external APFS SSD (not the default `/Applications`)

The cause (an app writing into its own bundle) and the fix (clone + ad hoc re-sign) aren't specific to Gigapixel: `fix-damaged-app.sh` takes any app path.

## License

MIT. Not affiliated with Topaz Labs. The real fix is on their side: store models outside the app bundle (e.g. `~/Library/Application Support`).
