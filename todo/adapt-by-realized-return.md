# Adapt when something stops working (his 10-22)

*"Right now we do a lot of air, humans realize it eventually and just make tons of AA... so what we need to do is
something OTHER than air at that point"*; *"Need some way to better adapt to whats going on in games. if one thing
isn't working, we have to learn/try something else."*

As a price, not a rule: each investment's worth learns from its realized return this game (an air strike's metal
killed per metal sent and lost, a ground push's, a nuke's), so a line that keeps failing prices itself down and the
money goes to what is working. Their AA seen is already an input; this closes the loop on outcomes.

Built: bomber runs weigh by bombers sent over the wing planned (apex_air_obs_evidence); gunship runs scored the same
way (8f907f1b, `gun run scored`); ground types carry a record (worth.as RecordMul). Missing: one realized return per
line (air, ground push, nukes, LRPC) that moves money between lines. The opposite failure, giving up on air too
soon, is `offensive-air-escalate.md`.
