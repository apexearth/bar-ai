# engine-patches

The C++ half of this AI, as a tracked patch.

`vendor/` is gitignored, and `vendor/engine/AI/Skirmish/BARb` is a submodule
sitting on a **detached HEAD with our work uncommitted**. Every C++ change this
AI has — the trade tracker, engage margin, the `drone` customparam fix,
juggernaut charge, the chase penalty, the commander patrol fix, the attack
hotspot, the BWEM chokepoint bindings — lived only in that working tree. A
`git checkout` or `git clean` in there would have destroyed all of it with
nothing to restore from.

`0001-barb-apex-cpp.patch` is `git diff` against:

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
