# Mass the long-range cannons on one area (his 10-18, 10-23)

His 10-18: one cannon may not get through their defence, but ten or twenty may, and then they have to spend on
shields, which are costly. His 10-23: *"When we make LRPC its kinda like nukes, we should have them all focusing
specific enemy areas which we want to defeat."*

Built: the battery fires as one at a focus cell, switched whole (brain/lrpc.as, apex_lrpc_focus, OFF, unmeasured);
a kill priced like a bomber's (apex_lrpc_prize, on). Not built: the price of the volley -- each cannon is priced as if
it kills alone and the next one is worth less; nothing prices the volley that breaks a position or the shields it
forces them to buy. Most of our gun orders die before the gun stands: `issues/lrpc-orders-die.md`.
