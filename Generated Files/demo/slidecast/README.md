# GMP/MPFR Windows Arm64 Slidecast pre-generation package

This authored package is offline-capable and intentionally stops before TTS/video generation. The deck visibly marks **x64 certification as UNRESOLVED** and native Arm64 proof as **PENDING**. Its narration and claims come from the current `demo-script.md`, `narration.txt`, `subtitles.srt`, and `impact-evidence.md`.

## Live preview

From this directory:

```powershell
Start-Process .\deck.html
```

Controls: arrows/click to navigate, `f` fullscreen, `c` live captions, `a` optional autoplay.

## Validate and capture stills

```powershell
$slidecastRoot = "C:\Users\yeelam\OneDrive - Microsoft\Documents\.copilot\skills\slidecast"
node "$slidecastRoot\scripts\capture_stills.js" --deck .\deck.html --storyboard .\storyboard.json --package-root . --out .\build\stills
```

## Final video render — only after both gates close

First resolve the x64 failures with clean validator summaries and run the locked process on a native Windows Arm64 machine. Replace all pending fields, update the deck/storyboard with verified evidence, and revalidate. Then:

```powershell
$slidecastRoot = "C:\Users\yeelam\OneDrive - Microsoft\Documents\.copilot\skills\slidecast"
python "$slidecastRoot\scripts\build.py" --storyboard .\storyboard.json --deck .\deck.html --package-root . --out .\build
```

Prerequisites: `pip install -r "$slidecastRoot\scripts\requirements.txt"`, installed Playwright Chromium for the bundled scripts, and `ffmpeg`/`ffprobe` on `PATH`.

Do not publish a success render while either `X64 CERTIFICATION: UNRESOLVED` or `ARM64 NATIVE: PENDING` remains. The current verified result is validator rejection with no certifying manifest.
