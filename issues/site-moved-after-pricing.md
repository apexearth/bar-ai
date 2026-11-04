# A site moved after pricing is a walk nobody priced (2026-10-15)

His watch game (army-smoke wdwatch1, t0, home 7600,4897): at 8.51 min `com-selfgun` hoisted an LLT at 7801,5336,
~480 elmos from the commander (`decide ... why=comself`, v=6.10). In the executor the defence-site net drew WALL
(`nndefsite` p: WALL 0.734, RULE 0.147), the best wall slot on the map, 11968,3776 -- 4,450 elmos from the priced
site. He walked 2.3 min, built the LLT at 10.9 min while the base fell, and `rehome` made that corner home.
Two holes: (1) `DefSitePick` relocates after `ValueOf`, and its features carry the distance from the rule's site
but not the asker's walk; (2) the commander leash in the decide loop (`ComFar(ranked[i].pos)`) tests the priced
pos, not the executed one, so a moved site escapes it. Whether the site net may move a self-defence gun, and how
far, is his call.
