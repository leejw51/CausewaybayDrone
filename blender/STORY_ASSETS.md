# Story scene assets

- Blender stage: `story_stage.blend`, built by `tools/build_story_stage.py`.
- Corrected humanoid: `cb_robot.blend`, built by `tools/build_cb_robot.py`.
- Runtime exports: `../godot/assets/story-stage.glb`, `../godot/assets/cb-robot.glb`.
- Sky: `../godot/assets/textures/story-sky-codex.png`.
- Generation: built-in Codex image generator, no user API key or fallback CLI.

Final sky texture prompt:

> A seamless 2:1 equirectangular panoramic sky texture for a polished whimsical 3D console adventure game's outdoor park story scene. Sky only: clean azure blue upper sky gradually transitioning to soft peach cream at the horizon, beautifully rounded fluffy stylized clouds clustered sparsely near horizon, subtle tiny magical sparkles high in sky. Cheerful late afternoon, painterly Nintendo-era adventure sensibility rendered clean and modern, readable shapes, understated gradients. No ground, landscape, buildings, characters, sun disc, lettering, border, or watermark. Left and right edges must tile seamlessly. Horizon at image vertical center. Intended as a Blender/Godot panorama sky material, not a concept scene.

## Cinematic title key art

Built-in Codex image generation, without a user API key. Runtime art is saved as
`../godot/assets/title-cinematic-wide-codex.png` and
`../godot/assets/title-cinematic-portrait-codex.png`.
Godot adds the actual title typography, exponential transitions, slow push-out and gold particles.

Wide prompt:

> Create a premium cinematic title-screen background for an original whimsical 3D game named Causewaybay Drone, WITHOUT ANY TEXT OR LETTERS. Wide 16:9 composition. Beautiful stylized Seoul Olympic Park at blue hour, soft sculpted rolling hills, distinctive distant wing-roof Peace Gate silhouette, a tiny warmly lit teal cafe, peach clouds and deep indigo starry sky. A friendly cream and teal six-rotor delivery drone with a small dark expressive face screen and a warm amber parcel flies through the lower right foreground, charming rounded game model, crisp clean materials, polished console adventure key art with a playful 16-bit color heritage. Golden delivery trail curves through the park from lower left to drone. Luminous rim light, rich navy and teal shadows, warm golden highlights. Keep central 60 percent especially upper center calm deep blue with beautiful atmospheric negative space for an oversized two-line game title added later. Not photorealistic, not Lego bricks. No text, no watermarks, no existing game characters or logos. Professional art direction, elegant depth and readable silhouette.

Portrait edit prompt (wide image as reference):

> Recompose this game title key art into a tall portrait 9:16 image for a vertical monitor. Preserve the same friendly cream/teal six-rotor drone, amber parcel, golden trail, whimsical park, wing-roof gate and blue-hour lighting. Put the drone in lower middle/right but entirely visible within the portrait frame, park and gate across the lower half. Upper 55 percent should be calm deep indigo sky with subtle stars and peach cloud edges, clear negative space for a large two-line title added in the game. Professional console game cover illustration. No letters, no text, no watermark. This is a portrait adaptation of the same scene, keep its identity and color palette.
