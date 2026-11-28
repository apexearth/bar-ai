#!/usr/bin/env python3
"""What the traced-back economy credit reaches: orders credited, how many of them are approach orders that the
near-the-target measures gave nothing (their own target far from the kill), and how far back the credit reaches.

    python tools/armynet/traced_check.py <dataset .npz>
"""
import sys

import numpy as np

z = np.load(sys.argv[1])
o, d = z["outcome"], z["decisions"]
if o.shape[2] < 8:
    sys.exit("built before the traced credit")
tr = o[:, 0, 7]
near10 = o[:, 4, 5]
got = tr > 0
print("orders: %d; with traced credit: %d (%.1f%%)" % (len(d), got.sum(), 100 * got.mean()))
print("  of them approach orders (no economy credit near their own target in 10 min): %d" % (got & (near10 <= 0)).sum())
print("  of them queued routes: %d" % (got & (d[:, 9] > 0)).sum())
print("traced credit per credited order (metal): median %.0f, q90 %.0f" % (np.median(tr[got]), np.percentile(tr[got], 90)))
_, first = np.unique(d[:, 7], return_index=True)
print("order groups credited: %d of %d" % ((tr[first] > 0).sum(), len(first)))
