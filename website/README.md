# ZETA LEGACY — Website

A dark, glassmorphism game landing page with **real-time 3D models** in the browser
and a direct **APK download**.

## What's inside
```
website/
├── index.html            # the page
├── styles.css            # dark space theme + glassmorphism
├── main.js               # starfield canvas, scroll reveals, live APK size
├── models/
│   ├── spaceship.glb     # 876 KB  (Draco + WebP, from 13.5 MB)
│   └── drone.glb         # 1.4 MB  (Draco + WebP, from 17 MB)
└── downloads/
    └── ZetaLegacy.apk    # the game (~137 MB)
```

## Tech
- **3D:** Google `<model-viewer>` (loaded from CDN) — decodes Draco + WebP natively,
  gives orbit, auto-rotate and PBR lighting with almost no code.
- **No build step.** Plain HTML/CSS/JS. Just serve the folder.

## Run locally
```bash
cd website
python3 -m http.server 8777
# open http://localhost:8777
```
(Models need to be served over http, not opened as file://.)

## Deploy (free options)
- **Netlify / Vercel / Cloudflare Pages:** drag the `website/` folder in. Done.
- **GitHub Pages:** push the folder, enable Pages.
- ⚠️ The 137 MB APK is the heavy part. GitHub Pages caps files at 100 MB, so for
  the APK either host it on a Release / external link, or use Netlify/Cloudflare
  (which allow it). The `<a download>` link just needs to point at wherever it lives.

## Re-compressing models (if you swap them)
Done with `@gltf-transform/cli` (wasm `sharp`):
```bash
gltf-transform optimize in.glb out.glb \
  --texture-compress webp --texture-size 1024 --compress draco
```
