ZETA LEGACY — Moon model swap folder
=====================================

Drop a .glb file here with one of these EXACT names and the game will use it
automatically — no code changes needed (models are runtime-loaded via ModelLib;
the editor importer is broken on this device, so do NOT import them).

  crater.glb      -> scattered across the moon surface as craters
  rock.glb        -> scattered as boulders/rocks
  robot_ball.glb  -> the companion bot "PIP" (the little robot ball)

Rules:
  - Real-world scale is auto-fit (centred + scaled), so size doesn't matter.
  - If a file is missing, the game falls back to a procedural placeholder.
  - Animated models: their baked animation auto-plays (looped). Rigged is fine too
    as long as the animation is baked into the .glb.
  - To revert to the placeholder, just delete/rename the file.

Example: to use your NASA crater model, rename it to `crater.glb` and copy it here.
