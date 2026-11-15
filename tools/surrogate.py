"""Can a model learn how our tunables move the outcome? Cross-validated surrogates.

    python tools/surrogate.py tournaments/ecoclimb-eco4/data.json

Each ecoclimb round played 8 games on one cell (seed, handicap, faction); the
target of a non-incumbent game is its ln(economy) minus the mean of that round's
incumbent games, so the cell's luck cancels and what is left is what the knob
changes did. Features are the 42 knobs in [0,1] knob space (ecoclimb.to_u).
Models are scored on ROUNDS THEY NEVER SAW (GroupKFold by round): R^2 and the
correlation of prediction with truth. A model that cannot beat "the knobs do
nothing" on held-out rounds has learned noise.
"""
import json
import sys

import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.linear_model import Ridge
from sklearn.model_selection import GroupKFold
from sklearn.neural_network import MLPRegressor
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import PolynomialFeatures, StandardScaler


def load(path):
    rows = json.load(open(path, encoding="utf-8"))
    base = {}
    for r in rows:
        if r["kind"] == "inc":
            base.setdefault(r["round"], []).append(r["y"])
    X, y, g, inc_u = [], [], [], {}
    for r in rows:
        if r["kind"] == "inc":
            inc_u[r["round"]] = r["u"]
    for r in rows:
        if r["kind"] == "inc" or r["round"] not in base:
            continue
        X.append(r["u"])
        y.append(r["y"] - sum(base[r["round"]]) / len(base[r["round"]]))
        g.append(r["round"])
    return np.array(X), np.array(y), np.array(g)


def main():
    X, y, g = load(sys.argv[1])
    print(f"{len(y)} non-baseline games in {len(set(g))} rounds; target sd {y.std():.3f}")
    models = {
        "zero (knobs do nothing)": None,
        "linear (ridge)": make_pipeline(StandardScaler(), Ridge(alpha=30.0)),
        "linear + squares": make_pipeline(PolynomialFeatures(2, interaction_only=False, include_bias=False),
                                          StandardScaler(), Ridge(alpha=300.0)),
        "boosted trees": HistGradientBoostingRegressor(max_depth=3, learning_rate=0.05, max_iter=200,
                                                       l2_regularization=1.0),
        "neural net 32x16": make_pipeline(StandardScaler(), MLPRegressor(hidden_layer_sizes=(32, 16), alpha=1.0,
                                                                          max_iter=3000, random_state=0)),
    }
    cv = GroupKFold(n_splits=5)
    for name, m in models.items():
        pred = np.zeros_like(y)
        for tr, te in cv.split(X, y, g):
            if m is None:
                pred[te] = 0.0
            else:
                m.fit(X[tr], y[tr])
                pred[te] = m.predict(X[te])
        ss = ((y - pred) ** 2).sum()
        r2 = 1.0 - ss / ((y - y.mean()) ** 2).sum()
        corr = np.corrcoef(pred, y)[0, 1] if pred.std() > 0 else 0.0
        print(f"  {name:26s} held-out R^2 {r2:+.3f}   corr {corr:+.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
