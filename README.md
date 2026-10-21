# Tab Target Test

A tiny cartoon-style, classic-WoW-style tab target prototype made in **Godot 4.6** (Compatibility renderer, so it runs on integrated graphics).

A hooded sorcerer in a purple robe, with a black void for a face, glowing red eyes and big white gloves, stands on a meadow with a training dummy. Target it and channel Force Lightning.

## Run it

1. Download this repo (Code → Download ZIP) and unzip it.
2. Open Godot 4.6, click **Import**, and pick `project.godot`.
3. Press **F5** to play.

## Controls

| Key / mouse | Action |
|---|---|
| W / S | Move forward / backpedal |
| A / D | Turn (strafe while holding right mouse) |
| Q / E | Strafe |
| Left mouse drag | Look around without turning |
| Right mouse drag | Steer the character |
| Both mouse buttons | Run forward |
| Mouse wheel | Zoom |
| Tab / click an enemy | Target |
| 1 | Force Lightning (channeled until interrupted) |
| Esc | Cancel cast / clear target |
| Num Lock | Autorun |
| F1 or H | Show / hide controls |

## How it works

- **Force Lightning**: channeled, 30 yard range, ticks every 0.5s. Moving, Esc, changing target or leaving range interrupts it. The caster turns to face the target automatically.
- **Training Dummy**: 2000 health, refills when it hits zero.
- Everything is built from smooth shapes in code and drawn with a cel-shading shader plus ink outlines (`shaders/`), so there are no model or texture files and it stays light on integrated graphics.

| File | What it does |
|---|---|
| `scripts/main.gd` | Builds the level, lighting and input keys |
| `scripts/player.gd` | Movement, targeting, casting, the sorcerer model, poses and hover cloud |
| `scripts/camera_rig.gd` | WoW-style mouse camera and click targeting |
| `scripts/force_lightning.gd` | The lightning effect |
| `scripts/training_dummy.gd` | The dummy |
| `scripts/hud.gd` | Player/target frames, cast bar, action bar |
| `scripts/toon.gd` | Toon materials, outlines and smooth shape helpers |
| `shaders/toon.gdshader` | Cel shading with tinted shadows, rim light and robe linings |
| `shaders/outline.gdshader` | Ink outlines that keep the same width on screen |

## Play in the browser

The web build lives on the `gh-pages` branch and is served by GitHub Pages:
https://kmad666.github.io/tab-target-test/

To rebuild it: in Godot, Project → Export → Web → Export Project into `build/web/`, then copy those files to the `gh-pages` branch. Thread support is off so it runs on GitHub Pages without special headers.
