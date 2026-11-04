# Scouting the army can use (his 10-22, 10-23)

His 10-22, after a player said our AI is "too afraid of static defenses": *"our AI needs more scouting. It often
doesn't understand what the enemy has and isn't sure what to do. Obvious answer is to make air scouts and use them
to help the army understand what they're up against."* His 10-23 game: no scout planes to see how strong their base
was; 0 `air look` flights in 37 minutes.

Air scouts priced by what an unknown costs the army: a fight decision made against a blind guess (FoeKnown false,
stale ghosts) is worth what a look would change in it. LookGainFor (air/state.as) prices a look only by what it adds
to the first bomber's prize; add what the army gains from knowing whether their base can be pushed. The look feeds
the army's own assessment (`docs/army.md`), not only the bomber wing's target choice.
