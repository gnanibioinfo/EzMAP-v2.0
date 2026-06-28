
# Classifiers

This folder holds the trained taxonomy classifiers (`*.qza`) used by EzMAP v2.0.

**The `.qza` files are not tracked in Git.** Each is roughly 3–210 MB, and the
largest exceed GitHub's 100 MB per-file limit, so only this README is committed.
On first run EzMAP copies any classifier found in this folder into your home
folder (`~/ezmap2-classifiers`, i.e. `C:\Users\<you>\ezmap2-classifiers`), so a
bundled distribution can pre-seed classifiers by placing them here.

## Option A — get them from inside EzMAP (recommended)

Launch EzMAP → **Database & Classifier Setup**:

- **Section 2 (Pre-trained):** click **Download** for a ready-to-use classifier.
- **Section 3 (Train):** train a region-specific classifier (needs a reference
  database from `db/` and ~16 GB+ RAM).

EzMAP saves the result to `~/ezmap2-classifiers` automatically.

## Option B — download manually

Save the files into this folder (or `~/ezmap2-classifiers`) using these exact
names that EzMAP expects:

| File | Target region | Source |
|------|---------------|--------|
| `silva-138-99-nb-classifier.qza` | Full-length 16S/18S (works for any region, incl. V4) | https://data.qiime2.org/classifiers/sklearn-1.4.2/silva/silva-138-99-nb-classifier.qza |
| `gg2-2024.09-full-length-nb-classifier.qza` | Full-length 16S | https://data.qiime2.org/classifiers/sklearn-1.4.2/greengenes2/2024.09.backbone.full-length.nb.sklearn-1.4.2.qza |
| `gg2-2024.09-v4-nb-classifier.qza` | 16S V4 (515F/806R) | https://data.qiime2.org/classifiers/sklearn-1.4.2/greengenes2/2024.09.backbone.v4.nb.sklearn-1.4.2.qza |
| `silva-16S-V3V4-nb-classifier.qza` | 16S V3–V4 | Train in EzMAP Section 3 (SILVA) |
| `unite-ITS1-nb-classifier.qza` | Fungal ITS1 | Train in EzMAP Section 3 (UNITE) |

## Notes

- **Version compatibility:** pre-trained classifiers are tied to a scikit-learn
  version. The ones above are **sklearn 1.4.2**, matching the QIIME 2 2024.10
  environment EzMAP installs. If QIIME reports a version mismatch, train a fresh
  classifier from the matching reference database in `db/`.
- **Memory:** training from a full reference database (especially SILVA) needs
  ~16 GB+ RAM. On smaller machines, download a pre-trained classifier instead —
  `silva-138-99-nb-classifier.qza` works for V3–V4 and any other 16S region.
- **Which to use:** 16S bacteria/archaea → SILVA or Greengenes2; fungal ITS →
  UNITE. A region-specific (trained) classifier gives ~5–10% better genus-level
  accuracy than a full-length one (Bokulich et al. 2018, *Microbiome*).
