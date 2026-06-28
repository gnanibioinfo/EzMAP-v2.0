package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Step 2 — Database & Classifier Setup (part of onboarding flow).
 *
 * Shows three sections:
 *   1. Reference Databases — download SILVA / Greengenes2 / UNITE
 *   2. Classifiers — quick-download pre-trained OR train region-specific
 *   3. Notes — accuracy guidance, when to train vs download
 *
 * The Continue button enables only when at least one classifier is available.
 */
public class DatabaseSetupPage extends BasePage {

    private final WizardController wizard;
    private final LogConsole console = new LogConsole();

    private final PrimaryButton continueBtn = new PrimaryButton("Continue to Mode Selection  \u2192");
    private final GhostButton   backBtn     = new GhostButton("\u2190  Back");
    private final JLabel         statusLabel = new JLabel(" ");

    // Inline status strips — one per section, shows progress right below the table
    private final JLabel dbStatusStrip    = createStatusStrip();
    private final JLabel ptStatusStrip    = createStatusStrip();
    private final JLabel trainStatusStrip = createStatusStrip();

    private static final String ENV_NAME = "EzMAP2-qiime2";
    private static final String CLASSIFIERS_DIR = "ezmap2-classifiers";
    private static final String DATABASES_DIR   = "ezmap2-databases";

    // ---- Reference database definitions ----
    // {display name, description, seqs filename, tax filename, seqs URL, tax URL}
    private static final String[][] DATABASES = {
        {"SILVA 138.2 (16S/18S)",
         "SSU 99% NR — sequences + taxonomy (~610 MB)",
         "silva-138.2-ssu-nr99-seqs.qza", "silva-138.2-ssu-nr99-tax.qza",
         "https://data.qiime2.org/2024.10/common/silva-138-99-seqs.qza",
         "https://data.qiime2.org/2024.10/common/silva-138-99-tax.qza"},
        {"Greengenes2 2024.09",
         "Full-length 16S — sequences + taxonomy (~68 MB)",
         "gg2-2024.09-nb-seqs.qza", "gg2-2024.09-nb-tax.qza",
         "http://ftp.microbio.me/greengenes_release/2024.09/2024.09.backbone.full-length.fna.qza",
         "http://ftp.microbio.me/greengenes_release/2024.09/2024.09.backbone.tax.qza"},
        {"UNITE 10.0 (ITS)",
         "Dynamic fungal ITS — manual download required",
         "unite-ver10-seqs-dynamic.qza", "unite-ver10-tax-dynamic.qza",
         "", ""},
    };

    // ---- Pre-trained classifier definitions ----
    // {display name, filename, URL, description}
    // URLs verified against the official QIIME 2 data resources index
    // (https://github.com/qiime2/resources). All three are scikit-learn 1.4.2
    // classifiers, matching the QIIME 2 2024.10 environment EzMAP2 installs.
    // NOTE: QIIME 2 no longer ships a region-specific SILVA classifier for
    // sklearn-1.4.2, so the previous (404-ing) silva-138-99-515-806 URL was
    // replaced with the Greengenes2 V4 classifier.
    private static final String[][] PRETRAINED_CLASSIFIERS = {
        {"SILVA 138 — Full-length (16S/18S)",
         "silva-138-99-nb-classifier.qza",
         "https://data.qiime2.org/classifiers/sklearn-1.4.2/silva/silva-138-99-nb-classifier.qza",
         "Generic 16S/18S — works on any region incl. V4 (~150 MB)"},
        {"Greengenes2 2024.09 — Full-length (16S)",
         "gg2-2024.09-full-length-nb-classifier.qza",
         "https://data.qiime2.org/classifiers/sklearn-1.4.2/greengenes2/2024.09.backbone.full-length.nb.sklearn-1.4.2.qza",
         "Greengenes2 full-length 16S (~100 MB)"},
        {"Greengenes2 2024.09 — V4 (515F/806R)",
         "gg2-2024.09-v4-nb-classifier.qza",
         "https://data.qiime2.org/classifiers/sklearn-1.4.2/greengenes2/2024.09.backbone.v4.nb.sklearn-1.4.2.qza",
         "Optimized for V4 (515F/806R) amplicons (~75 MB)"},
    };

    // ---- Region-specific training definitions ----
    // {amplicon, database tag, output filename}
    private static final String[][] TRAINABLE_CLASSIFIERS = {
        {"16S-V3V4", "silva",       "silva-16S-V3V4-nb-classifier.qza"},
        {"16S-V4",   "silva",       "silva-16S-V4-nb-classifier.qza"},
        {"16S-V3V4", "greengenes2", "greengenes2-16S-V3V4-nb-classifier.qza"},
        {"16S-V4",   "greengenes2", "greengenes2-16S-V4-nb-classifier.qza"},
        {"ITS1",     "unite",       "unite-ITS1-nb-classifier.qza"},
        {"ITS2",     "unite",       "unite-ITS2-nb-classifier.qza"},
    };

    // Tables
    private final DefaultTableModel dbModel = new DefaultTableModel(
            new String[]{"Database", "Description", "Status", "Action"}, 0) {
        @Override public boolean isCellEditable(int r, int c) { return c == 3; }
    };
    private final DefaultTableModel ptModel = new DefaultTableModel(
            new String[]{"Classifier", "Description", "Status", "Action"}, 0) {
        @Override public boolean isCellEditable(int r, int c) { return c == 3; }
    };
    private final DefaultTableModel trainModel = new DefaultTableModel(
            new String[]{"Amplicon", "Database", "Status", "Action"}, 0) {
        @Override public boolean isCellEditable(int r, int c) { return c == 3; }
    };

    private volatile boolean busy = false;

    public DatabaseSetupPage(WizardController wizard) {
        super("Database & Classifier Setup",
              "Download reference databases and classifiers before running your analysis. "
              + "You need at least one classifier to proceed.");
        this.wizard = wizard;

        // ---- Section 1: Reference Databases ----
        Card dbCard = new Card("1 · Reference Databases");
        JLabel dbDesc = new JLabel("<html><body style='width:660px'>"
                + "Reference databases contain the sequences and taxonomy used to train classifiers. "
                + "SILVA is recommended for 16S/18S bacterial/archaeal studies, UNITE for fungal ITS. "
                + "Download these only if you plan to train region-specific classifiers (Step 3 below)."
                + "</body></html>");
        dbDesc.setFont(Theme.FONT_SMALL);
        dbDesc.setForeground(Theme.INK_3);
        dbCard.row(dbDesc);
        dbCard.gap(6);

        JTable dbTable = createStyledTable(dbModel);
        dbTable.getColumnModel().getColumn(0).setPreferredWidth(180);
        dbTable.getColumnModel().getColumn(1).setPreferredWidth(280);
        dbTable.getColumnModel().getColumn(2).setPreferredWidth(130);
        dbTable.getColumnModel().getColumn(3).setPreferredWidth(90);
        dbTable.getColumnModel().getColumn(3).setCellRenderer(new ActionRenderer());
        dbTable.getColumnModel().getColumn(3).setCellEditor(new ActionEditor(dbTable, this::onDbAction));

        JScrollPane dbScroll = new JScrollPane(dbTable);
        dbScroll.setPreferredSize(new Dimension(0, 118));
        dbScroll.setBorder(BorderFactory.createLineBorder(Theme.BORDER, 1, true));
        dbCard.row(dbScroll);
        dbCard.row(dbStatusStrip);
        add(dbCard);

        // ---- Section 2: Pre-trained Classifiers (Quick) ----
        Card ptCard = new Card("2 · Pre-trained Classifiers  (Quick — download ready-to-use)");

        JPanel quickBanner = new JPanel(new BorderLayout(10, 0));
        quickBanner.setOpaque(true);
        quickBanner.setBackground(new Color(0xEF, 0xF6, 0xFF));
        quickBanner.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(new Color(0xBF, 0xDB, 0xFE), 1, true),
                new EmptyBorder(10, 14, 10, 14)));
        JLabel quickIcon = new JLabel("\u26A1", SwingConstants.CENTER);
        quickIcon.setFont(Theme.FONT_BODY_BOLD.deriveFont(18f));
        quickIcon.setForeground(Theme.ACCENT);
        quickBanner.add(quickIcon, BorderLayout.WEST);
        JLabel quickText = new JLabel("<html><b>Fastest option</b> — download a pre-trained classifier "
                + "and start analyzing immediately. These are trained on full-length sequences "
                + "and work on any amplicon region.</html>");
        quickText.setFont(Theme.FONT_SMALL);
        quickText.setForeground(Theme.INK_2);
        quickBanner.add(quickText, BorderLayout.CENTER);
        ptCard.row(quickBanner);
        ptCard.gap(6);

        JTable ptTable = createStyledTable(ptModel);
        ptTable.getColumnModel().getColumn(0).setPreferredWidth(250);
        ptTable.getColumnModel().getColumn(1).setPreferredWidth(250);
        ptTable.getColumnModel().getColumn(2).setPreferredWidth(110);
        ptTable.getColumnModel().getColumn(3).setPreferredWidth(90);
        ptTable.getColumnModel().getColumn(3).setCellRenderer(new ActionRenderer());
        ptTable.getColumnModel().getColumn(3).setCellEditor(new ActionEditor(ptTable, this::onPtAction));

        JScrollPane ptScroll = new JScrollPane(ptTable);
        ptScroll.setPreferredSize(new Dimension(0, 118));
        ptScroll.setBorder(BorderFactory.createLineBorder(Theme.BORDER, 1, true));
        ptCard.row(ptScroll);
        ptCard.gap(6);

        JPanel importRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        importRow.setOpaque(false);
        OutlineButton importBtn = new OutlineButton("Import Existing Classifier (.qza)…");
        importBtn.addActionListener(e -> importClassifier());
        importRow.add(importBtn);
        JLabel importHint = new JLabel("Already have a classifier? Import it directly.");
        importHint.setFont(Theme.FONT_SMALL);
        importHint.setForeground(Theme.INK_3);
        importRow.add(importHint);
        ptCard.row(importRow);
        ptCard.row(ptStatusStrip);

        add(ptCard);

        // ---- Section 3: Train Region-Specific Classifiers (Recommended) ----
        Card trainCard = new Card("3 · Train Region-Specific Classifier  (Recommended — higher accuracy)");

        JPanel recBanner = new JPanel(new BorderLayout(10, 0));
        recBanner.setOpaque(true);
        recBanner.setBackground(Theme.PRIMARY_SOFT);
        recBanner.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.PRIMARY_BORDER, 1, true),
                new EmptyBorder(10, 14, 10, 14)));
        JLabel recIcon = new JLabel("\u2713", SwingConstants.CENTER);
        recIcon.setFont(Theme.FONT_BODY_BOLD.deriveFont(18f));
        recIcon.setForeground(Theme.PRIMARY_DARK);
        recBanner.add(recIcon, BorderLayout.WEST);
        JLabel recText = new JLabel("<html><b>Best accuracy</b> — trains a classifier specific to your "
                + "primer pair and amplicon region. Requires a reference database (Step 1). "
                + "Takes 20–60 minutes but gives ~5–10% better genus-level classification."
                + "</html>");
        recText.setFont(Theme.FONT_SMALL);
        recText.setForeground(Theme.INK_2);
        recBanner.add(recText, BorderLayout.CENTER);
        trainCard.row(recBanner);
        trainCard.gap(6);

        JTable trainTable = createStyledTable(trainModel);
        trainTable.getColumnModel().getColumn(0).setPreferredWidth(110);
        trainTable.getColumnModel().getColumn(1).setPreferredWidth(140);
        trainTable.getColumnModel().getColumn(2).setPreferredWidth(140);
        trainTable.getColumnModel().getColumn(3).setPreferredWidth(90);
        trainTable.getColumnModel().getColumn(3).setCellRenderer(new ActionRenderer());
        trainTable.getColumnModel().getColumn(3).setCellEditor(new ActionEditor(trainTable, this::onTrainAction));

        JScrollPane trainScroll = new JScrollPane(trainTable);
        trainScroll.setPreferredSize(new Dimension(0, 185));
        trainScroll.setBorder(BorderFactory.createLineBorder(Theme.BORDER, 1, true));
        trainCard.row(trainScroll);
        trainCard.row(trainStatusStrip);
        add(trainCard);

        // ---- Notes Section ----
        Card notesCard = new Card("Notes & Guidance");
        JLabel notes = new JLabel("<html><body style='width:660px'>"
                + "<b>Which classifier should I use?</b><br>"
                + "\u2022 <b>First-time users:</b> Download a pre-trained classifier (Section 2) to get started quickly. "
                + "You can always train a region-specific one later.<br>"
                + "\u2022 <b>For publication:</b> Train a region-specific classifier (Section 3) matched to your "
                + "exact primers. Bokulich et al. (2018, <i>Microbiome</i>) showed ~5–10% improvement in "
                + "genus-level accuracy with region-specific training.<br>"
                + "\u2022 <b>16S studies:</b> SILVA 138.2 is the most widely used. Greengenes2 is an alternative "
                + "with updated phylogeny.<br>"
                + "\u2022 <b>ITS (fungal) studies:</b> UNITE 10.0 is required. Download manually from "
                + "<b>unite.ut.ee</b> (licensing), then train a region-specific classifier.<br>"
                + "\u2022 <b>Classifier compatibility:</b> Pre-trained classifiers are tied to the QIIME2 + scikit-learn "
                + "version. If you get a version mismatch error, train a new classifier from reference data.<br><br>"
                + "<b>Storage:</b> Reference databases use ~600 MB (SILVA) to ~200 MB (GG2). "
                + "Each trained classifier is ~100–300 MB. Pre-trained downloads are ~100–150 MB each."
                + "</body></html>");
        notes.setFont(Theme.FONT_SMALL);
        notes.setForeground(Theme.INK_2);
        notesCard.row(notes);
        add(notesCard);

        // ---- Log Console ----
        Card logCard = new Card("Activity Log");
        console.setPreferredSize(new Dimension(0, 150));
        logCard.row(console);
        add(logCard);

        // ---- Status line on its own full-width row so it wraps and never
        //      overlaps the Back/Continue buttons. ----
        statusLabel.setFont(Theme.FONT_SMALL);
        statusLabel.setForeground(Theme.INK_3);
        statusLabel.setBorder(new EmptyBorder(8, 2, 2, 2));
        add(statusLabel);

        // ---- Navigation: Back + Continue ----
        JPanel navRow = new JPanel(new BorderLayout());
        navRow.setOpaque(false);
        navRow.setBorder(new EmptyBorder(0, 0, 0, 0));

        JPanel rightBtns = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        rightBtns.setOpaque(false);
        backBtn.addActionListener(e -> wizard.previous());
        continueBtn.setEnabled(false);
        continueBtn.addActionListener(e -> wizard.next());
        rightBtns.add(backBtn);
        rightBtns.add(continueBtn);
        navRow.add(rightBtns, BorderLayout.EAST);
        add(navRow);
    }

    // ========================================================================
    // Lifecycle
    // ========================================================================
    @Override
    public void onShown() {
        new Thread(() -> {
            seedBundledClassifiers();
            refreshAllTables();
            updateContinueState();
        }).start();
    }

    /**
     * Seed the user's ~/ezmap2-classifiers/ folder with the classifiers that
     * ship with EzMAP2 (the application's classifier/ folder, next to the JAR),
     * so a first-time user has a ready-to-use classifier WITHOUT downloading
     * anything. Existing files are never overwritten, so a user's own
     * downloaded/trained classifiers are left untouched. A missing bundle
     * folder is a harmless no-op, and any failure is non-fatal (the user can
     * still download or import a classifier).
     */
    private void seedBundledClassifiers() {
        try {
            File bundleDir = locateBundledClassifierDir();
            if (bundleDir == null) return;
            File[] qzas = bundleDir.listFiles((d, n) -> n.endsWith("-nb-classifier.qza"));
            if (qzas == null || qzas.length == 0) return;

            Path clDir = getClDir();
            Files.createDirectories(clDir);
            int copied = 0;
            for (File q : qzas) {
                Path dest = clDir.resolve(q.getName());
                if (Files.exists(dest)) continue;          // never overwrite
                Files.copy(q.toPath(), dest);
                console.ok("Bundled classifier ready: " + q.getName());
                copied++;
            }
            if (copied > 0) {
                console.info(copied + " bundled classifier(s) installed to "
                        + clDir + " — you can start right away, or download/train more below.");
            }
        } catch (Exception e) {
            console.warn("Could not install bundled classifiers: " + e.getMessage()
                    + " (you can still download or import one).");
        }
    }

    /** Locate the application's bundled classifier/ folder (ships next to the JAR). */
    private File locateBundledClassifierDir() {
        java.util.List<File> tries = new java.util.ArrayList<>();
        try {
            String jarPath = DatabaseSetupPage.class.getProtectionDomain()
                    .getCodeSource().getLocation().getPath();
            File jarDir = new File(java.net.URLDecoder.decode(jarPath, "UTF-8")).getParentFile();
            if (jarDir != null) {
                tries.add(new File(jarDir, "classifier"));                 // deployed: next to JAR
                File p1 = jarDir.getParentFile();
                if (p1 != null) {
                    tries.add(new File(p1, "classifier"));                 // dev: target/ -> src-build/
                    File p2 = p1.getParentFile();
                    if (p2 != null) tries.add(new File(p2, "classifier")); // dev: -> repo root
                }
            }
        } catch (Exception ignored) {}
        File projectDir = new File(System.getProperty("user.dir"));
        tries.add(new File(projectDir, "classifier"));
        if (projectDir.getParentFile() != null)
            tries.add(new File(projectDir.getParentFile(), "classifier"));

        for (File f : tries) {
            if (f != null && f.isDirectory()) return f;
        }
        return null;
    }

    // ========================================================================
    // Table refresh
    // ========================================================================
    private void refreshAllTables() {
        refreshDatabaseTable();
        refreshPretrainedTable();
        refreshTrainTable();
    }

    private void refreshDatabaseTable() {
        SwingUtilities.invokeLater(() -> dbModel.setRowCount(0));
        Path dbDir = getDbDir();
        for (String[] db : DATABASES) {
            String name     = db[0];
            String desc     = db[1];
            String seqsFile = db[2];
            String taxFile  = db[3];
            boolean seqsOk  = Files.exists(dbDir.resolve(seqsFile));
            boolean taxOk   = Files.exists(dbDir.resolve(taxFile));
            String status, action;
            if (seqsOk && taxOk) {
                status = "\u2713  Ready";
                action = "Delete";
            } else if (name.contains("UNITE") && db[4].isEmpty()) {
                status = "\u2717  Not imported";
                action = "Import";
            } else {
                status = "\u2717  Missing";
                action = "Download";
            }
            SwingUtilities.invokeLater(() -> dbModel.addRow(new Object[]{name, desc, status, action}));
        }
    }

    private void refreshPretrainedTable() {
        SwingUtilities.invokeLater(() -> ptModel.setRowCount(0));
        Path clDir = getClDir();
        for (String[] pt : PRETRAINED_CLASSIFIERS) {
            String name = pt[0];
            String file = pt[1];
            String desc = pt[3];
            boolean exists = Files.exists(clDir.resolve(file));
            String status = exists ? "\u2713  Ready" : "\u2717  Not downloaded";
            String action = exists ? "Delete" : "Download";
            SwingUtilities.invokeLater(() -> ptModel.addRow(new Object[]{name, desc, status, action}));
        }
    }

    private void refreshTrainTable() {
        SwingUtilities.invokeLater(() -> trainModel.setRowCount(0));
        Path clDir = getClDir();
        for (String[] tr : TRAINABLE_CLASSIFIERS) {
            String amplicon = tr[0];
            String dbTag    = tr[1];
            String file     = tr[2];
            boolean exists  = Files.exists(clDir.resolve(file));
            String status   = exists ? "\u2713  Ready" : "\u2717  Not trained";
            String action   = exists ? "Delete" : "Train";
            SwingUtilities.invokeLater(() -> trainModel.addRow(new Object[]{amplicon, dbTag, status, action}));
        }
    }

    private void updateContinueState() {
        // List the classifiers present in ~/ezmap2-classifiers/ so the user can
        // see exactly WHICH ones are available (e.g. an ITS-only set must not be
        // mistaken as ready for a bacterial 16S V3\u2013V4 run).
        Path clDir = getClDir();
        java.util.List<String> names = new java.util.ArrayList<>();
        if (Files.isDirectory(clDir)) {
            try (java.util.stream.Stream<Path> s = Files.list(clDir)) {
                s.filter(p -> p.toString().endsWith(".qza"))
                 // Skip hidden/temporary artifacts (e.g. the .tmp-extracted-reads.qza
                 // left behind by training) — they are not usable classifiers.
                 .filter(p -> !p.getFileName().toString().startsWith("."))
                 .map(p -> prettyClassifier(p.getFileName().toString()))
                 .sorted()
                 .forEach(names::add);
            } catch (IOException ignored) {}
        }
        final boolean ready = !names.isEmpty();
        final String joined = String.join(", ", names);
        SwingUtilities.invokeLater(() -> {
            // Never enable Continue while a download/training is in progress.
            continueBtn.setEnabled(ready && !busy);
            if (ready) {
                statusLabel.setText("<html><body style='width:660px'>"
                        + "<span style='color:#16A34A'>\u2713 Available classifier(s): <b>"
                        + joined + "</b></span>"
                        + " <span style='color:#B45309'>\u2014 confirm one matches your amplicon "
                        + "(16S vs ITS) before continuing.</span></body></html>");
                statusLabel.setForeground(Theme.INK_2);
            } else {
                statusLabel.setText("Download or train at least one classifier to continue.");
                statusLabel.setForeground(Theme.WARNING);
            }
        });
    }

    /** Toggle the busy flag and lock navigation while a long operation runs, so
     *  the user cannot click Back/Continue and abandon a download or training. */
    private void setBusy(boolean b) {
        busy = b;
        SwingUtilities.invokeLater(() -> {
            backBtn.setEnabled(!b);
            if (b) continueBtn.setEnabled(false);
        });
        if (!b) updateContinueState();
    }

    /** Turn a classifier filename into a short, readable label for the status line. */
    private static String prettyClassifier(String fileName) {
        String s = fileName;
        if (s.endsWith(".qza")) s = s.substring(0, s.length() - 4);
        if (s.endsWith("-nb-classifier")) s = s.substring(0, s.length() - "-nb-classifier".length());
        return s;
    }

    // ========================================================================
    // Actions — database table
    // ========================================================================
    private void onDbAction(int row, String action) {
        if (row < 0 || row >= DATABASES.length) return;
        String[] db = DATABASES[row];
        if ("Download".equals(action)) {
            downloadDatabase(db);
        } else if ("Delete".equals(action)) {
            deleteDatabase(db);
        } else if ("Import".equals(action)) {
            importDatabase(db);
        }
    }

    private void downloadDatabase(String[] db) {
        if (busy) {
            showBusyWarning(dbStatusStrip);
            return;
        }
        String name = db[0];
        String seqsFile = db[2], taxFile = db[3];
        String seqsUrl  = db[4], taxUrl  = db[5];
        if (seqsUrl.isEmpty()) { showUniteInfo(); return; }

        setBusy(true);
        // Find the row index for this database to update its action cell
        int row = findDbRow(name);
        setRowAction(dbModel, row, "Downloading\u2026");
        setStatusBusy(dbStatusStrip, "Downloading " + name + " — this may take several minutes\u2026");
        console.info("Downloading " + name + "…");

        new Thread(() -> {
            try {
                Path dir = getDbDir();
                Files.createDirectories(dir);
                setStatusBusy(dbStatusStrip, "Downloading sequences file\u2026");
                downloadFile(seqsUrl, dir.resolve(seqsFile).toString());
                console.ok("Downloaded: " + seqsFile);
                setStatusBusy(dbStatusStrip, "Downloading taxonomy file\u2026");
                downloadFile(taxUrl, dir.resolve(taxFile).toString());
                console.ok("Downloaded: " + taxFile);
                console.ok(name + " ready.");
                setStatusDone(dbStatusStrip, "\u2713  " + name + " downloaded successfully.");
                refreshDatabaseTable();
                refreshTrainTable();
            } catch (Exception e) {
                console.err("Download failed: " + e.getMessage());
                setStatusError(dbStatusStrip, "Download failed: " + e.getMessage());
                refreshDatabaseTable();
            } finally {
                setBusy(false);
            }
        }).start();
    }

    private void deleteDatabase(String[] db) {
        int ok = JOptionPane.showConfirmDialog(this,
                "Delete " + db[0] + " reference files?", "Confirm",
                JOptionPane.YES_NO_OPTION, JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;
        Path dir = getDbDir();
        try {
            Files.deleteIfExists(dir.resolve(db[2]));
            Files.deleteIfExists(dir.resolve(db[3]));
            console.ok("Deleted: " + db[0]);
            refreshDatabaseTable();
        } catch (IOException e) { console.err("Delete failed: " + e.getMessage()); }
    }

    /**
     * Import existing .qza files from user's local disk (for UNITE or any database).
     * Opens a file chooser for sequences .qza, then taxonomy .qza, and copies them
     * to ~/ezmap2-databases/ with the expected filenames.
     */
    private void importDatabase(String[] db) {
        String name     = db[0];
        String seqsFile = db[2];
        String taxFile  = db[3];

        JFileChooser fc = new JFileChooser();
        fc.setDialogTitle("Select " + name + " — Reference Sequences (.qza)");
        fc.setFileFilter(new javax.swing.filechooser.FileNameExtensionFilter(
                "QIIME2 Artifact (.qza)", "qza"));

        if (fc.showOpenDialog(this) != JFileChooser.APPROVE_OPTION) return;
        File seqsSrc = fc.getSelectedFile();

        fc.setDialogTitle("Select " + name + " — Taxonomy (.qza)");
        if (fc.showOpenDialog(this) != JFileChooser.APPROVE_OPTION) return;
        File taxSrc = fc.getSelectedFile();

        console.info("Importing " + name + " from local files…");
        console.info("  Sequences: " + seqsSrc.getAbsolutePath());
        console.info("  Taxonomy:  " + taxSrc.getAbsolutePath());

        new Thread(() -> {
            try {
                Path dir = getDbDir();
                Files.createDirectories(dir);
                Files.copy(seqsSrc.toPath(), dir.resolve(seqsFile),
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                console.ok("Imported: " + seqsFile);
                Files.copy(taxSrc.toPath(), dir.resolve(taxFile),
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                console.ok("Imported: " + taxFile);
                console.ok(name + " imported and ready.");
                refreshDatabaseTable();
                refreshTrainTable();
            } catch (Exception e) {
                console.err("Import failed: " + e.getMessage());
            }
        }).start();
    }

    // ========================================================================
    // Actions — pre-trained classifier table
    // ========================================================================
    private void onPtAction(int row, String action) {
        if (row < 0 || row >= PRETRAINED_CLASSIFIERS.length) return;
        String[] pt = PRETRAINED_CLASSIFIERS[row];
        if ("Download".equals(action)) {
            downloadPretrained(pt);
        } else if ("Delete".equals(action)) {
            deletePretrained(pt);
        } else if ("Import".equals(action)) {
            importClassifier();
        }
    }

    private void downloadPretrained(String[] pt) {
        if (busy) {
            showBusyWarning(ptStatusStrip);
            return;
        }
        setBusy(true);
        String name = pt[0], file = pt[1], url = pt[2];
        int row = findPtRow(name);
        setRowAction(ptModel, row, "Downloading\u2026");
        setStatusBusy(ptStatusStrip, "Downloading " + name + " — please wait\u2026");
        console.info("Downloading pre-trained classifier: " + name + "…");

        new Thread(() -> {
            try {
                Path dir = getClDir();
                Files.createDirectories(dir);
                downloadFile(url, dir.resolve(file).toString());
                console.ok("Downloaded: " + file);
                setStatusDone(ptStatusStrip, "\u2713  " + name + " — ready for use!");
                refreshPretrainedTable();
                updateContinueState();
            } catch (Exception e) {
                console.err("Download failed: " + e.getMessage());
                setStatusError(ptStatusStrip, "Download failed. Try again or train a region-specific classifier.");
                refreshPretrainedTable();
            } finally {
                setBusy(false);
            }
        }).start();
    }

    private void deletePretrained(String[] pt) {
        int ok = JOptionPane.showConfirmDialog(this,
                "Delete pre-trained classifier " + pt[0] + "?", "Confirm",
                JOptionPane.YES_NO_OPTION, JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;
        try {
            Files.deleteIfExists(getClDir().resolve(pt[1]));
            console.ok("Deleted: " + pt[1]);
            refreshPretrainedTable();
            updateContinueState();
        } catch (IOException e) { console.err("Delete failed: " + e.getMessage()); }
    }

    /**
     * Import an existing classifier .qza from user's disk into ~/ezmap2-classifiers/.
     * Preserves the original filename so it appears in the classifier dropdown.
     */
    private void importClassifier() {
        JFileChooser fc = new JFileChooser();
        fc.setDialogTitle("Select Existing Classifier (.qza)");
        fc.setFileFilter(new javax.swing.filechooser.FileNameExtensionFilter(
                "QIIME2 Classifier (.qza)", "qza"));
        fc.setMultiSelectionEnabled(true);

        if (fc.showOpenDialog(this) != JFileChooser.APPROVE_OPTION) return;

        File[] files = fc.getSelectedFiles();
        console.info("Importing " + files.length + " classifier file(s)…");

        new Thread(() -> {
            try {
                Path dir = getClDir();
                Files.createDirectories(dir);
                for (File f : files) {
                    Path dest = dir.resolve(f.getName());
                    Files.copy(f.toPath(), dest,
                            java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    console.ok("Imported: " + f.getName());
                }
                console.ok("Import complete. " + files.length + " classifier(s) added.");
                refreshPretrainedTable();
                refreshTrainTable();
                updateContinueState();
            } catch (Exception e) {
                console.err("Import failed: " + e.getMessage());
            }
        }).start();
    }

    // ========================================================================
    // Actions — train table
    // ========================================================================
    private void onTrainAction(int row, String action) {
        if (row < 0 || row >= TRAINABLE_CLASSIFIERS.length) return;
        String[] tr = TRAINABLE_CLASSIFIERS[row];
        if ("Train".equals(action)) {
            trainClassifier(tr);
        } else if ("Delete".equals(action)) {
            deleteTrainable(tr);
        }
    }

    private void trainClassifier(String[] tr) {
        if (busy) {
            showBusyWarning(trainStatusStrip);
            return;
        }
        String amplicon = tr[0], dbTag = tr[1], outFile = tr[2];

        // Verify reference DB is downloaded
        boolean dbReady = false;
        Path dbDir = getDbDir();
        for (String[] db : DATABASES) {
            if (db[0].toLowerCase().contains(dbTag)) {
                dbReady = Files.exists(dbDir.resolve(db[2])) && Files.exists(dbDir.resolve(db[3]));
                break;
            }
        }
        if (!dbReady) {
            setStatusError(trainStatusStrip,
                    "Reference database for '" + dbTag + "' not downloaded. Download it in Section 1 first.");
            console.err("Reference database for '" + dbTag + "' not downloaded.");
            return;
        }

        setBusy(true);
        int row = findTrainRow(amplicon, dbTag);
        setRowAction(trainModel, row, "Training\u2026");
        setStatusBusy(trainStatusStrip,
                "Training " + amplicon + " / " + dbTag + " — this takes 20–60 minutes. Do not close EzMAP v2.0.");
        console.info("Training classifier: " + amplicon + " / " + dbTag);
        console.info("Output: " + outFile);

        new Thread(() -> {
            try {
                String scriptDir = findScriptsDir();
                // On Windows, override the default ~/ezmap2-* paths to use
                // WSL-accessible /mnt/c/... paths so Java can find the output
                String envOverride = "";
                String os2 = System.getProperty("os.name").toLowerCase();
                if (os2.contains("win")) {
                    envOverride = "export CLASSIFIERS_DIR=\"" + shellPath(getClDir()) + "\"; "
                               + "export DOWNLOADS_DIR=\"" + shellPath(getDbDir()) + "\"; ";
                }
                String cmd = envOverride
                        + "bash \"" + scriptDir + "/train_classifier.sh\""
                        + " --database " + dbTag
                        + " --amplicon " + amplicon;
                runShellStreaming(cmd);
                console.ok("Training complete: " + outFile);
                setStatusDone(trainStatusStrip, "\u2713  " + amplicon + " / " + dbTag + " classifier trained!");
                refreshTrainTable();
                updateContinueState();
            } catch (Exception e) {
                console.err("Training failed: " + e.getMessage());
                setStatusError(trainStatusStrip, "Training failed: " + e.getMessage());
                refreshTrainTable();
            } finally {
                setBusy(false);
            }
        }).start();
    }

    private void deleteTrainable(String[] tr) {
        int ok = JOptionPane.showConfirmDialog(this,
                "Delete trained classifier " + tr[0] + " / " + tr[1] + "?", "Confirm",
                JOptionPane.YES_NO_OPTION, JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;
        try {
            Files.deleteIfExists(getClDir().resolve(tr[2]));
            console.ok("Deleted: " + tr[2]);
            refreshTrainTable();
            updateContinueState();
        } catch (IOException e) { console.err("Delete failed: " + e.getMessage()); }
    }

    // ========================================================================
    // UNITE manual info
    // ========================================================================
    private void showUniteInfo() {
        console.info("UNITE requires manual download due to licensing.");
        console.info("Visit: https://unite.ut.ee/repository.php");
        console.info("Download QIIME2-formatted dynamic release (ver 10.0).");
        console.info("Save to: " + getDbDir());

        JOptionPane.showMessageDialog(this,
                "<html><body style='width:460px'>"
                + "<b>UNITE Database — Manual Download Required</b><br><br>"
                + "UNITE requires registration and license agreement.<br><br>"
                + "1. Visit <b>https://unite.ut.ee/repository.php</b><br>"
                + "2. Download the QIIME2-formatted dynamic release (ver 10.0)<br>"
                + "3. Import into .qza format if needed<br>"
                + "4. Click the <b>Import</b> button in the Reference Databases table<br>"
                + "5. Select the sequences .qza first, then the taxonomy .qza<br><br>"
                + "EzMAP v2.0 will copy them to the correct location with the expected filenames."
                + "</body></html>",
                "UNITE Download", JOptionPane.INFORMATION_MESSAGE);
    }

    // ========================================================================
    // Shell / download helpers
    // ========================================================================
    private static String condaInitPreamble() {
        return "for d in \"$HOME/miniconda3\" \"$HOME/miniforge3\" \"$HOME/mambaforge\" "
             + "\"$HOME/anaconda3\" \"/opt/miniconda3\" \"/opt/conda\"; do "
             + "  if [ -f \"$d/etc/profile.d/conda.sh\" ]; then "
             + "    . \"$d/etc/profile.d/conda.sh\"; break; "
             + "  fi; "
             + "done; "
             + "conda activate " + ENV_NAME + " 2>/dev/null; ";
    }

    private void runShellStreaming(String cmd) throws Exception {
        String os = System.getProperty("os.name").toLowerCase();
        String fullCmd = condaInitPreamble() + cmd;
        ProcessBuilder pb;
        if (os.contains("win")) {
            pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--",
                    "bash", "-lc", fullCmd);
        } else {
            pb = new ProcessBuilder("bash", "-lc", fullCmd);
        }
        pb.redirectErrorStream(true);
        Process p = pb.start();
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                String ln = line;
                if (ln.contains("\u2713") || ln.contains("complete") || ln.contains("done")) {
                    console.ok(ln);
                } else if (ln.contains("\u26A0") || ln.contains("warning")) {
                    console.warn(ln);
                } else if (ln.contains("\u2717") || ln.contains("error") || ln.contains("fail")) {
                    console.err(ln);
                } else {
                    console.info(ln);
                }
            }
        }
        int rc = p.waitFor();
        if (rc != 0) {
            // Codes that mean the process was killed or crashed rather than
            // failing cleanly — almost always OUT OF MEMORY, since training a
            // Naive Bayes classifier from the full SILVA reference needs ~16 GB+ RAM:
            //   137 = 128+9  (SIGKILL / OOM-killer)
            //   143 = 128+15 (SIGTERM)
            //   139 = 128+11 (SIGSEGV — segmentation fault, the typical symptom of
            //                 fit-classifier-naive-bayes exhausting memory)
            //   134 = 128+6  (SIGABRT)
            if (rc == 137 || rc == 143 || rc == 139 || rc == 134 || rc == 15 || rc == 9) {
                throw new RuntimeException("the training process was killed or crashed (e.g. a "
                    + "segmentation fault) — almost always OUT OF MEMORY. Training a classifier from the "
                    + "full reference database (especially SILVA) needs ~16 GB+ RAM, which exceeds what WSL "
                    + "has by default. Options: (1) use a pre-trained classifier instead — in Section 2 "
                    + "download 'SILVA 138 — Full-length', which works for V3–V4 and any other 16S region "
                    + "(no training needed); or (2) give WSL more memory by creating %USERPROFILE%\\.wslconfig "
                    + "with [wsl2] then memory=24GB, run 'wsl --shutdown', and retry training.");
            }
            throw new RuntimeException("the command exited with code " + rc);
        }
    }

    private void downloadFile(String url, String dest) throws Exception {
        String fname = url.substring(url.lastIndexOf('/') + 1);
        console.info("  Fetching: " + fname);
        // On Windows, convert the dest path to WSL-accessible /mnt/ path
        String os = System.getProperty("os.name").toLowerCase();
        boolean win = os.contains("win");
        String shellDest = win ? toWslPath(Paths.get(dest)) : dest;

        // Remove any stale/partial file from a previous failed attempt
        try { Files.deleteIfExists(Paths.get(dest)); } catch (Exception ignored) {}

        // Ensure the directory exists in the shell context
        String mkdirCmd = "mkdir -p \"$(dirname \"" + shellDest + "\")\"";
        // IMPORTANT: curl -f makes HTTP errors (404/500) return a non-zero exit
        // code WITHOUT writing the error page to disk. The previous code used
        // "curl -o" (no -f), which happily saved a 1 KB "404 Not Found" page as
        // the .qza file and reported success — exactly the reviewer's bug.
        // -L follows the data.qiime2.org redirects; wget is only a fallback.
        String dlCmd = "curl -fSL --retry 3 --retry-delay 2 -o \"" + shellDest + "\" \"" + url + "\""
                + " || wget --tries=3 -O \"" + shellDest + "\" \"" + url + "\"";
        String cmd = mkdirCmd + " && " + dlCmd;
        ProcessBuilder pb;
        if (win) {
            pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc", cmd);
        } else {
            pb = new ProcessBuilder("bash", "-lc", cmd);
        }
        pb.redirectErrorStream(true);
        Process p = pb.start();
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) console.info("  " + line);
        }
        int rc = p.waitFor();
        if (rc != 0) {
            try { Files.deleteIfExists(Paths.get(dest)); } catch (Exception ignored) {}
            throw new RuntimeException("Could not download " + fname
                    + " (network error or file unavailable on server).");
        }
        // Verify the result is a real QIIME2 archive, not an HTML error page.
        verifyQza(Paths.get(dest), fname);
    }

    /**
     * Validate a downloaded .qza file. A genuine QIIME2 artifact is a ZIP archive
     * (starts with the "PK" signature) and is many megabytes; a failed download
     * typically leaves a tiny HTML "404 Not Found" page. If the file fails either
     * check it is deleted and an exception is thrown so the UI shows a clear error
     * instead of silently treating a broken file as "Ready".
     */
    private void verifyQza(Path file, String fname) throws Exception {
        long size = Files.exists(file) ? Files.size(file) : -1;
        boolean isZip = false;
        if (size >= 4) {
            try (InputStream in = Files.newInputStream(file)) {
                byte[] sig = new byte[4];
                int n = in.read(sig);
                // PK\x03\x04 (normal), PK\x05\x06 (empty), PK\x07\x08 (spanned)
                isZip = n == 4 && sig[0] == 0x50 && sig[1] == 0x4B
                        && (sig[2] == 0x03 || sig[2] == 0x05 || sig[2] == 0x07);
            }
        }
        if (!isZip || size < 100_000) {
            try { Files.deleteIfExists(file); } catch (Exception ignored) {}
            throw new RuntimeException("Downloaded file '" + fname + "' is not a valid QIIME2 archive ("
                    + (size < 0 ? "no file received" : (size / 1024) + " KB")
                    + "). The download URL may be unavailable. The invalid file was removed.");
        }
        console.ok("  Verified: " + fname + " (" + (size / (1024 * 1024)) + " MB)");
    }

    // ========================================================================
    // Path helpers
    // ========================================================================

    /**
     * On Windows, we store databases and classifiers under the Windows user home
     * (e.g., C:\Users\gnani\ezmap2-classifiers) so Java can check file existence.
     * Downloads via WSL use the /mnt/c/... path to write to the same location.
     * On Linux/macOS, it's simply ~/ezmap2-classifiers.
     */
    private Path getDbDir() {
        return Paths.get(System.getProperty("user.home"), DATABASES_DIR);
    }

    private Path getClDir() {
        return Paths.get(System.getProperty("user.home"), CLASSIFIERS_DIR);
    }

    /** Convert a Windows path to a WSL-accessible /mnt/ path for shell commands. */
    private String toWslPath(Path windowsPath) {
        String p = windowsPath.toString().replace('\\', '/');
        // C:/Users/gnani/... → /mnt/c/Users/gnani/...
        if (p.length() >= 2 && p.charAt(1) == ':') {
            p = "/mnt/" + Character.toLowerCase(p.charAt(0)) + p.substring(2);
        }
        return p;
    }

    /** Get the shell-usable path for downloads (WSL /mnt/ path on Windows, native on Linux/macOS). */
    private String shellPath(Path dir) {
        String os = System.getProperty("os.name").toLowerCase();
        if (os.contains("win")) {
            return toWslPath(dir);
        }
        return dir.toString();
    }

    private String findScriptsDir() {
        String[] candidates = {"scripts", "EzMAP2_redesign/scripts",
                System.getProperty("user.dir") + "/scripts"};
        for (String c : candidates) {
            if (new File(c, "train_classifier.sh").exists()) return c;
        }
        return "scripts";
    }

    // ========================================================================
    // Inline status strip helpers
    // ========================================================================
    private static JLabel createStatusStrip() {
        JLabel strip = new JLabel(" ");
        strip.setFont(Theme.FONT_SMALL);
        strip.setForeground(Theme.INK_3);
        strip.setBorder(new EmptyBorder(2, 4, 2, 4));
        strip.setOpaque(true);
        strip.setBackground(Theme.BACKGROUND);
        strip.setVisible(false);
        return strip;
    }

    private void setStatusBusy(JLabel strip, String msg) {
        SwingUtilities.invokeLater(() -> {
            strip.setText("\u23F3  " + msg);
            strip.setForeground(Theme.ACCENT);
            strip.setBackground(new Color(0xEF, 0xF6, 0xFF));
            strip.setVisible(true);
            strip.repaint();
        });
    }

    private void setStatusDone(JLabel strip, String msg) {
        SwingUtilities.invokeLater(() -> {
            strip.setText(msg);
            strip.setForeground(Theme.SUCCESS);
            strip.setBackground(Theme.PRIMARY_SOFT);
            strip.setVisible(true);
            strip.repaint();
        });
    }

    private void setStatusError(JLabel strip, String msg) {
        SwingUtilities.invokeLater(() -> {
            strip.setText("\u2717  " + msg);
            strip.setForeground(Theme.DANGER);
            strip.setBackground(new Color(0xFE, 0xE2, 0xE2));
            strip.setVisible(true);
            strip.repaint();
        });
    }

    private void showBusyWarning(JLabel strip) {
        SwingUtilities.invokeLater(() -> {
            strip.setText("\u26A0  Another operation is in progress — please wait.");
            strip.setForeground(Theme.WARNING);
            strip.setBackground(new Color(0xFF, 0xF7, 0xE6));
            strip.setVisible(true);
            strip.repaint();
        });
    }

    /** Update a table row's action column (last column) to show progress text. */
    private void setRowAction(DefaultTableModel model, int row, String text) {
        if (row < 0 || row >= model.getRowCount()) return;
        SwingUtilities.invokeLater(() -> model.setValueAt(text, row, model.getColumnCount() - 1));
    }

    /** Find the row index for a database by its display name. */
    private int findDbRow(String name) {
        for (int i = 0; i < dbModel.getRowCount(); i++) {
            if (name.equals(dbModel.getValueAt(i, 0))) return i;
        }
        return -1;
    }

    /** Find the row index for a pre-trained classifier by its display name. */
    private int findPtRow(String name) {
        for (int i = 0; i < ptModel.getRowCount(); i++) {
            if (name.equals(ptModel.getValueAt(i, 0))) return i;
        }
        return -1;
    }

    /** Find the row index for a trainable classifier by amplicon + db tag. */
    private int findTrainRow(String amplicon, String dbTag) {
        for (int i = 0; i < trainModel.getRowCount(); i++) {
            if (amplicon.equals(trainModel.getValueAt(i, 0))
                    && dbTag.equals(trainModel.getValueAt(i, 1))) return i;
        }
        return -1;
    }

    // ========================================================================
    // Table styling and action handling
    // ========================================================================
    private static JTable createStyledTable(DefaultTableModel model) {
        JTable table = new JTable(model);
        table.setFont(Theme.FONT_SMALL);
        table.setRowHeight(30);
        table.setShowGrid(false);
        table.setIntercellSpacing(new Dimension(0, 0));
        table.setSelectionBackground(Theme.PRIMARY_SOFT);
        table.setSelectionForeground(Theme.INK_1);
        table.setBackground(Theme.SURFACE);
        table.getTableHeader().setFont(Theme.FONT_LABEL);
        table.getTableHeader().setBackground(Theme.SURFACE_2);
        table.getTableHeader().setForeground(Theme.INK_2);
        table.getTableHeader().setBorder(
                BorderFactory.createMatteBorder(0, 0, 1, 0, Theme.BORDER));

        DefaultTableCellRenderer cellRenderer = new DefaultTableCellRenderer();
        cellRenderer.setBorder(new EmptyBorder(0, 8, 0, 8));
        for (int i = 0; i < table.getColumnCount() - 1; i++) {
            table.getColumnModel().getColumn(i).setCellRenderer(cellRenderer);
        }
        return table;
    }

    /** Renders the action column as a clickable label. */
    private static class ActionRenderer extends DefaultTableCellRenderer {
        @Override
        public Component getTableCellRendererComponent(JTable t, Object val, boolean sel,
                                                       boolean focus, int row, int col) {
            JLabel lbl = (JLabel) super.getTableCellRendererComponent(t, val, sel, focus, row, col);
            String text = val != null ? val.toString() : "";
            lbl.setHorizontalAlignment(SwingConstants.CENTER);
            lbl.setFont(Theme.FONT_BUTTON);
            if ("Download".equals(text) || "Train".equals(text) || "Import".equals(text)) {
                lbl.setForeground(Theme.PRIMARY_DARK);
                lbl.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
            } else if ("Delete".equals(text)) {
                lbl.setForeground(Theme.DANGER);
                lbl.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
            } else if (text.contains("\u2026")) {
                // "Downloading…" or "Training…" — show as busy/disabled
                lbl.setForeground(Theme.INK_3);
                lbl.setFont(Theme.FONT_SMALL.deriveFont(Font.ITALIC));
                lbl.setCursor(Cursor.getPredefinedCursor(Cursor.WAIT_CURSOR));
            } else {
                lbl.setForeground(Theme.INK_3);
                lbl.setCursor(Cursor.getPredefinedCursor(Cursor.DEFAULT_CURSOR));
            }
            return lbl;
        }
    }

    /** Functional interface for action callbacks. */
    @FunctionalInterface
    private interface ActionCallback {
        void run(int row, String action);
    }

    /** Handles clicks in the action column and delegates to a callback. */
    private static class ActionEditor extends DefaultCellEditor {
        private String value;
        private int editingRow;
        private final ActionCallback callback;

        ActionEditor(JTable table, ActionCallback callback) {
            super(new JTextField());
            this.callback = callback;
            setClickCountToStart(1);
        }

        @Override
        public Component getTableCellEditorComponent(JTable t, Object val, boolean sel, int row, int col) {
            value = val != null ? val.toString() : "";
            editingRow = row;
            SwingUtilities.invokeLater(() -> {
                fireEditingStopped();
                // Ignore clicks on busy cells (Downloading…, Training…)
                if (!value.contains("\u2026")) {
                    callback.run(editingRow, value);
                }
            });
            JLabel lbl = new JLabel(value, SwingConstants.CENTER);
            lbl.setFont(Theme.FONT_BUTTON);
            lbl.setForeground(Theme.PRIMARY_DARK);
            return lbl;
        }

        @Override public Object getCellEditorValue() { return value; }
    }
}
