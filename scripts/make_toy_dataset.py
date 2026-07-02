#!/usr/bin/env python3
"""
make_toy_dataset.py — Generate the EzMAP2 toy example dataset.

Creates a tiny, deterministic 16S rRNA dataset (12 samples, 60 ASVs, 7-level
taxonomy, with planted Control/Drought differential signal) for testing the
EzMAP2 Downstream Analysis module:

    example-data/feature-table-tax.biom   (BIOM v2.1, with taxonomy)
    example-data/metadata.tsv             (QIIME 2-style sample metadata)
    example-data/rooted-tree.nwk          (Newick tree over all ASVs)

Requirements:  pip install biom-format h5py numpy
Usage:         python scripts/make_toy_dataset.py
"""
import os
import numpy as np
import biom
from biom.util import biom_open

# Output directory: <repo>/example-data  (sibling of this script's parent)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(HERE), "example-data")
os.makedirs(OUT_DIR, exist_ok=True)

rng = np.random.default_rng(42)  # fixed seed → reproducible

# ---- Design: 12 samples, 6 Control + 6 Drought ----
samples = [f"C{i}" for i in range(1, 7)] + [f"D{i}" for i in range(1, 7)]
groups = ["Control"] * 6 + ["Drought"] * 6
n_samp = len(samples)

# ---- Plausible soil/plant-associated bacterial lineages (7 levels) ----
lineages = [
    ("Bacteria", "Proteobacteria", "Gammaproteobacteria", "Pseudomonadales", "Pseudomonadaceae", "Pseudomonas", "fluorescens"),
    ("Bacteria", "Proteobacteria", "Gammaproteobacteria", "Enterobacterales", "Enterobacteriaceae", "Enterobacter", "cloacae"),
    ("Bacteria", "Proteobacteria", "Alphaproteobacteria", "Rhizobiales", "Rhizobiaceae", "Rhizobium", "leguminosarum"),
    ("Bacteria", "Proteobacteria", "Alphaproteobacteria", "Sphingomonadales", "Sphingomonadaceae", "Sphingomonas", "yabuuchiae"),
    ("Bacteria", "Proteobacteria", "Betaproteobacteria", "Burkholderiales", "Burkholderiaceae", "Burkholderia", "cepacia"),
    ("Bacteria", "Actinobacteriota", "Actinobacteria", "Streptomycetales", "Streptomycetaceae", "Streptomyces", "coelicolor"),
    ("Bacteria", "Actinobacteriota", "Actinobacteria", "Micrococcales", "Micrococcaceae", "Arthrobacter", "globiformis"),
    ("Bacteria", "Actinobacteriota", "Actinobacteria", "Corynebacteriales", "Nocardiaceae", "Rhodococcus", "erythropolis"),
    ("Bacteria", "Firmicutes", "Bacilli", "Bacillales", "Bacillaceae", "Bacillus", "subtilis"),
    ("Bacteria", "Firmicutes", "Bacilli", "Lactobacillales", "Lactobacillaceae", "Lactobacillus", "plantarum"),
    ("Bacteria", "Firmicutes", "Clostridia", "Clostridiales", "Clostridiaceae", "Clostridium", "butyricum"),
    ("Bacteria", "Bacteroidota", "Bacteroidia", "Cytophagales", "Cytophagaceae", "Cytophaga", "hutchinsonii"),
    ("Bacteria", "Bacteroidota", "Bacteroidia", "Flavobacteriales", "Flavobacteriaceae", "Flavobacterium", "johnsoniae"),
    ("Bacteria", "Acidobacteriota", "Acidobacteriae", "Acidobacteriales", "Acidobacteriaceae", "Acidobacterium", "capsulatum"),
    ("Bacteria", "Verrucomicrobiota", "Verrucomicrobiae", "Chthoniobacterales", "Chthoniobacteraceae", "Chthoniobacter", "flavus"),
    ("Bacteria", "Gemmatimonadota", "Gemmatimonadetes", "Gemmatimonadales", "Gemmatimonadaceae", "Gemmatimonas", "aurantiaca"),
    ("Bacteria", "Planctomycetota", "Planctomycetes", "Planctomycetales", "Planctomycetaceae", "Planctomyces", "brasiliensis"),
    ("Bacteria", "Chloroflexi", "Chloroflexia", "Chloroflexales", "Chloroflexaceae", "Chloroflexus", "aurantiacus"),
]

n_asv = 60
feat_ids = [f"ASV{i}" for i in range(1, n_asv + 1)]
tax = [list(lineages[i % len(lineages)]) for i in range(n_asv)]  # full 7-level taxonomy

# ---- Counts with planted group signal ----
base_abund = rng.lognormal(mean=3.0, sigma=1.2, size=n_asv)
counts = np.zeros((n_asv, n_samp), dtype=int)

diff_idx = rng.choice(n_asv, size=14, replace=False)
effect = np.ones(n_asv)
for k, idx in enumerate(diff_idx):
    fold = rng.uniform(2.5, 6.0)
    effect[idx] = fold if k % 2 == 0 else 1.0 / fold  # half up in Drought, half in Control

for j in range(n_samp):
    drought = groups[j] == "Drought"
    for i in range(n_asv):
        mu = base_abund[i] * (effect[i] if drought else 1.0)
        mu_j = mu * rng.uniform(0.7, 1.3)
        counts[i, j] = rng.poisson(max(mu_j, 0.05))

# Guard against empty samples / all-zero ASVs
counts[counts.sum(axis=1) == 0, 0] = 1
for j in range(n_samp):
    if counts[:, j].sum() == 0:
        counts[0, j] = 5

# ---- Write BIOM (with taxonomy + sample metadata) ----
obs_md = [{"taxonomy": t} for t in tax]
samp_md = [{"Condition": g} for g in groups]
table = biom.Table(counts, feat_ids, samples,
                   observation_metadata=obs_md, sample_metadata=samp_md)
biom_path = os.path.join(OUT_DIR, "feature-table-tax.biom")
with biom_open(biom_path, "w") as f:
    table.to_hdf5(f, "EzMAP2 toy dataset generator")

# ---- Write metadata.tsv (QIIME 2-style, with #q2:types row) ----
meta_path = os.path.join(OUT_DIR, "metadata.tsv")
with open(meta_path, "w") as m:
    m.write("sample-id\tCondition\tReplicate\n")
    m.write("#q2:types\tcategorical\tnumeric\n")
    for s, g in zip(samples, groups):
        m.write(f"{s}\t{g}\t{s[1:]}\n")

# ---- Write a random rooted bifurcating tree (tips == feature IDs) ----
def random_tree(tips):
    nodes = [f"{t}:{round(rng.uniform(0.05, 0.4), 3)}" for t in tips]
    rng.shuffle(nodes)
    while len(nodes) > 1:
        a, b = nodes.pop(), nodes.pop()
        nodes.append(f"({a},{b}):{round(rng.uniform(0.05, 0.3), 3)}")
    return nodes[0] + ";"

tree_path = os.path.join(OUT_DIR, "rooted-tree.nwk")
with open(tree_path, "w") as t:
    t.write(random_tree(list(feat_ids)) + "\n")

print("Wrote:")
for p in (biom_path, meta_path, tree_path):
    print(f"  {p}  ({os.path.getsize(p)} bytes)")
print(f"\n{n_asv} ASVs x {n_samp} samples | {len(diff_idx)} differential ASVs "
      f"(Control vs Drought)")
