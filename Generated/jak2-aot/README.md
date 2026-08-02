# Generated/jak2-aot

Jak II's GOAL code, ahead-of-time compiled to C by `goalc-cbackend-sweep`: one `.c` and one
`_generated.h` per object file in `goal_src/jak2/game.gp` build order, plus the manifest that names
all 840 object translations.

The generated sources and coverage report are local build products and are never committed. Generate
and verify them with:

```sh
Scripts/generate-jak2-aot.sh
```

This directory is intentionally not part of the GOALPad app target. Jak 1 and Jak II emit overlapping
global symbols, so each game's AOT code must be compiled into a mutually exclusive product. The first
Jak II Apple-platform milestone is an iPhoneOS compile/link proof, not a gameplay claim.
