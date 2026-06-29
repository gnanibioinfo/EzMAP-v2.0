# Classifiers

This folder holds trained taxonomy classifiers (`*.qza`) for EzMAP v2.0.

**No classifier files are shipped in Git** (they exceed GitHub's 100 MB limit).
On first run EzMAP copies any `.qza` placed here into `~/ezmap2-classifiers`
(`C:\Users\<you>\ezmap2-classifiers`). A distribution *could* pre-seed classifiers
by dropping them here, but the standard build ships none — you download or train
one inside the app (below).

## Getting a classifier (EzMAP → Database & Classifier Setup)

### Section 2 — Pre-trained (recommended, no training)

Click **Download** for a ready-to-use classifier. Full-length SILVA or
Greengenes2 classify **any 16S region** (V3–V4, V4, …), so this is all most users
need.

| Classifier | Region | sklearn |
|------------|--------|---------|
| SILVA 138 — Full-length | 16S/18S, any region | 1.4.2 |
| Greengenes2 2024.09 — Full-length | 16S, any region | 1.4.2 |
| Greengenes2 2024.09 — V4 (515F/806R) | 16S V4 | 1.4.2 |

### Advanced — Train a custom classifier

For **fungal ITS** or **non-standard primers**, open the **Advanced** section,
enter your forward/reverse primers (defaults are 16S V3–V4 and ITS1), and click
**Train**. Training builds the classifier from the matching reference database —
downloaded automatically for SILVA/Greengenes2, and bundled in `db/` for UNITE —
and saves it here as `<database>-custom-nb-classifier.qza`, after which it appears
in the available-classifier list. Training needs ~16 GB+ RAM and can take ~3 hours.

## Notes

- **Version compatibility:** classifiers are tied to a scikit-learn version. The
  downloads above are **sklearn 1.4.2**, matching the QIIME 2 2024.10 environment
  EzMAP installs. On a version-mismatch error, train a fresh classifier.
- **Why full-length is fine:** QIIME 2 no longer ships region-specific classifiers
  because, in practice, they perform comparably to full-length ones for any region
  — so for 16S you rarely need to train at all.
