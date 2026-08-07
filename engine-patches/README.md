# engine-patches

The C++ half of this AI, as a tracked patch.

`vendor/` is gitignored, and `vendor/engine/AI/Skirmish/BARb` is a submodule
sitting on a **detached HEAD with our work uncommitted**. Every C++ change this
AI has — the trade tracker, engage margin, the `drone` customparam fix,
juggernaut charge, the chase penalty, the commander patrol fix, the attack
hotspot, the BWEM chokepoint bindings — lived only in that working tree. A
`git checkout` or `git clean` in there would have destroyed all of it with
nothing to restore from.

## 0001-barb-apex-cpp.patch

`git diff` in the `AI/Skirmish/BARb` submodule, against:

    base commit 0ef36267633d6c1b2f6408a8d8a59fff38745dc3
    ("Add move_state tag. Add PatrolTask for static constructors.
      AS: Add IUnitTask::Abort/Done")

Re-export after any C++ change:

    cd vendor/engine/AI/Skirmish/BARb && git diff > ../../../../../engine-patches/0001-barb-apex-cpp.patch

Re-apply onto a fresh clone:

    cd vendor/engine/AI/Skirmish/BARb
    git checkout 0ef36267633d6c1b2f6408a8d8a59fff38745dc3
    git apply ../../../../../engine-patches/0001-barb-apex-cpp.patch

This is a backstop, not a workflow. It does not merge, and it will conflict if
the submodule is advanced. Re-export is manual and therefore easy to forget —
if the patch's timestamp is older than the DLL you are running, the patch is
stale, not the tree.

## 0002-build-sh-no-tty.patch

One line in `vendor/engine` itself (base commit
`01b3161aa5d9d2c6583825da174c439ad9df4908`): `docker run -it` -> `-i`. There is
no TTY in a non-interactive shell, so `-it` aborts the build with
"the input device is not a TTY". Only needed if you build via
`docker-build-v2/build.sh` rather than invoking `ninja` in the container
directly, which is what the commands in `docs/06-building-the-dll.md` do.
