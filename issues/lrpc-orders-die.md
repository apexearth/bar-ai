# Our long-range gun orders die: ~85-90% never finish (2026-10-24)

His ask: our own LRPC massing (he won Canis River with ~17; ours stop at 0-8 a seat). Measured, 2v2 +100 vs v0.4.0,
Starwatcher + FolsomDamR, four 8-game runs (`tournaments/20261024-0239*`, `-0330*`, `-0411*`, `-0450*`):
- Orders are not the limit: 613 gun orders in one run. Tasks are: 2-25% of gun tasks end in a finished gun per run,
  in BOTH versions (pooled ~11%). Deaths: frames killed (`target-killed`), `unreach-safe` (C++ refuses the road for
  threat), `hurt-retreat`. 85-95% of elected sites stood >3000 from the seat's start; the guns built stood at 150-2300.
- The site is the heavy defence's (`SuperSite(SC_HEAVY)`): a gate, the edge of the ground the team holds -- in a 2v2
  the hull of both allies (Starwatcher allies start ~6,000 apart). From home the gun reaches nothing on these maps
  (reach gain 11-17 vs 127-252 at gates): standing forward is right; surviving there is the problem.
- THE DEFECT: the risk model reads those gate sites at survival 0.44-0.50 over the build (`StreamSurvivalOver`) while
  ~4% of tasks begun there finish. Killed frames never entered the loss field (only `WasFinished` deaths do); adding
  them (cost x progress) moved gate survival 0.50 -> 0.44 only. Three site changes were measured and reverted
  (26af972c / e39762ca): none moved completion.
- In his hosted games the failure differs: no `unreach-safe`; frames killed even near base, and early the
  affordability gate (bill > a minute of income).
- His 10-24 answer: build there; if it fails, porc up and defend the area. Tried (b55b9eec / 9bc6be2b, reverted):
  a failed gun site as stake (turrets near failed sites 44 vs v0.4.0's 45), then also as a defence site (16 vs 52).
  The defence market will not buy at those sites -- its PRICE there (stake vs the forward threat, the target
  already met) is the next thing to read, with a defprice line for those sites. Also open: a realized-completion
  price on the gun itself. Unstable still carries apex_lrpc_prize (1c52e5a4, on): neutral, 2-2.
