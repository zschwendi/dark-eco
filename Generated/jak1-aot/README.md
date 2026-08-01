# Generated/jak1-aot

Jak 1's GOAL code, ahead-of-time compiled to C by `goalc-cbackend-sweep`: one `.c` and one
`_generated.h` per object file in `goal_src/jak1/game.gp` build order, plus `aot_boot_manifest.c`,
which names them all in that order.

Nothing here is committed. The directory itself is, because the app target picks these files up as
a synchronized folder and Xcode needs it to exist.

```sh
Scripts/generate-jak1-aot.sh
```

Run that after cloning and whenever the `OpenGOAL` submodule pin moves. It builds the host sweep
tool and writes ~1039 files here. They are compiled for the iPad by the `GOALPad` target with
`GCC_STRICT_ALIASING = NO`, which is required: GOAL reads and writes the same memory at several
widths, exactly as the x86-64 backend does.
