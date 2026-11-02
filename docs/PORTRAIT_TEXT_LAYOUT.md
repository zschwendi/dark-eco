# Portrait in-game text

Experimental in Build 286; tracked in [issue #21](https://github.com/zschwendi/dark-eco/issues/21).

Full-screen portrait Fit keeps the world projection introduced in Build 285.
On conventional iOS hosts, the font path instead uses the available width for
text sizing when Fit to Screen is enabled and the game viewport is portrait.
It uniformly scales glyphs, their measured advances and multiline line height;
it preserves authored anchors and tab stops. Landscape, square, Fit-off,
macOS and visionOS retain their previous sizing.

The host reports `q = (width / height) / (4/3)` only for portrait Fit. Jak 1
applies q temporarily to the six small/large glyph size vectors and restores
them after drawing or measurement. Jak II temporarily multiplies the existing
font-context scale. Both paths use the same correction for wrapping and line
height, skip custom font matrices, and include labels projected into the
default UI matrix. This is a font correction, not a redesign of authored menu
panels or non-text HUD geometry.

The portable native query returns float bits through the GOAL integer-register
ABI. Both games are regenerated as ahead-of-time code together with their
matching public source-object packs. Existing valid imports resolve font/text
objects to the current linked AOT units at boot; a game-data reimport is not
required. No game assets are bundled in this change.

Validation must distinguish native ABI/source-pack checks, simulator visual
checks and physical playtesting. The first two do not establish physical
performance or every dialogue/menu layout.
