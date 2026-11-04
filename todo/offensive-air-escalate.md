# Don't give up on offensive air; escalate (his 10-24)

*"I think the AI fairly quickly thinks that making air is not worth it. We just have a small/medium amount of fighters
and don't really put much effort into bombers"*; *"if the humans make fighters or AA we seem to kinda give up... on
the idea of offensive air"*. And: *"make even bigger and bigger attacks, until we're making huge massive attacks. or
build up 20 dragons supported by fighters... that genuinely would work a lot of the time"*.

His 10-24 hosted game: runs of 14/0, 6/0, 5/0 home, 26->2, 41->7; after them NaEval floors every wing's losses at the
last run's (obsSurv/obsLost), the held wing sits at the count and nothing else is tried.

The answer to "their AA beats our air" is a different move, priced: strike the AA itself first
(`strike-their-aa.md`), mass past it, escort with fighters against their fighters -- and let a failed run's lesson
fade, since their AA dies and moves. NaEval values ONE cell, while a surviving mass works through their base cell
after cell: price a wing on the cells it survives to reach, so the planned wing (gNaNeedN) grows after a failure
instead of the price falling to zero. Tried for gunships as apex_air_chain and reverted (2f894376: worse on
gunship_aa_hidden). Rich seats buy bombers past the count while they pay (apex_air_rich, on for every seat since
10-30).
