package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.io.*;

/**
 * Expert Mode — Step 3: Primer removal with Cutadapt.
 *
 * Features:
 *   - Auto barcode/primer detection: BarcodeDetector scans reads on page load
 *   - If barcodes/primers detected → Skip is disabled, user must run Cutadapt
 *   - If reads are clean → Skip is enabled
 *   - Auto CPU core detection: recommends optimal thread count
 *   - Live command preview
 *
 * Runs: qiime cutadapt trim-paired (or trim-single)
 */
public class CutadaptPage extends BasePage {

    private final WizardController wizard;
    private boolean stepComplete = false;

    @Override public boolean isStepComplete() { return stepComplete; }

    // Input
    private final DirectoryPicker demuxPicker;

    // Amplicon & Primers (defaults shown, user can edit)
    private final JComboBox<String> ampliconCombo = new JComboBox<>(
            new String[]{"16S-V3V4", "16S-V4", "ITS1", "ITS2", "Custom"});
    private final JTextField fwdPrimerField = new JTextField(30);
    private final JTextField revPrimerField = new JTextField(30);
    private final JSpinner   minLenSpinner  = spinner(50, 1, 500, 10);
    private final JCheckBox  discardBox     = new JCheckBox("Discard untrimmed reads", true);
    private final JSpinner   errorRateSpinner = spinnerDouble(0.1, 0.0, 1.0, 0.05);
    private final JSpinner   timesSpinner     = spinner(1, 1, 10, 1);
    private final JSpinner   overlapSpinner   = spinner(3, 1, 50, 1);
    private final JSpinner   coresSpinner;

    // Skip
    private final OutlineButton skipBtn = new OutlineButton("Skip Cutadapt \u2192");

    // Controls
    private final PrimaryButton runBtn = new PrimaryButton("Run Cutadapt  \u2192");
    private final OutlineButton stopBtn = new OutlineButton("Stop");
    private final JLabel statusLabel = new JLabel(" ");
    private final LogConsole console = new LogConsole();
    private final JTextArea cmdPreview = new JTextArea(3, 60);

    private volatile QiimeCommand runningCmd;

    // Barcode/linker auto-detection (single source of truth for primer presence)
    private final Card barcodeCard;
    private final JLabel barcodeIcon;
    private final JLabel barcodeTitle;
    private final JLabel barcodeBody;
    private final JPanel barcodeBtnRow;
    private final OutlineButton btnBarcodeDismiss = new OutlineButton("Dismiss");
    private volatile boolean barcodeDetectionRunning = false;
    private volatile BarcodeDetector.DetectionResult lastBarcodeResult = null;

    // Primer defaults per amplicon
    private static final String[][] PRIMER_DEFAULTS = {
        {"16S-V3V4", "CCTACGGGNGGCWGCAG",      "GACTACHVGGGTATCTAATCC"},
        {"16S-V4",   "GTGYCAGCMGCCGCGGTAA",    "GGACTACNVGGGTWTCTAAT"},
        {"ITS1",     "CTTGGTCATTTAGAGGAAGTAA",  "GCTGCGTTCTTCATCGATGC"},
        {"ITS2",     "GCATCGATGAAGAACGCAGC",    "TCCTCCGCTTATTGATATGC"},
    };

    public CutadaptPage(WizardController wizard) {
        super("Expert Mode — Step 4: Primer Removal (Cutadapt)",
              "Remove primer sequences from your reads using Cutadapt. " +
              "EzMAP v2.0 automatically scans your reads to determine if primers/barcodes are present.");
        this.wizard = wizard;

        // ---- Auto-detect CPU cores ----
        int detectedCores = Runtime.getRuntime().availableProcessors();
        int recommendedCores = Math.max(1, detectedCores - 1);  // leave 1 for system
        coresSpinner = spinner(recommendedCores, 0, 128, 1);

        // ---- Card 1: Input ----
        Card inputCard = new Card("1 \u00B7 Input");
        inputCard.row(caption("Demux .qza file (from Import step):"));
        demuxPicker = new DirectoryPicker("Select demux .qza",
                f -> { refreshRunState(); triggerBarcodeDetection(); }, true);
        inputCard.row(demuxPicker);
        add(inputCard);

        // ---- Barcode/Linker Auto-Detection Card (initially hidden) ----
        // This is the SINGLE source of truth for primer/barcode presence.
        // When detected → Skip is disabled. When clean → Skip is enabled.
        barcodeCard = new Card(null);
        barcodeCard.setVisible(false);

        JPanel barcodeInner = new JPanel(new BorderLayout(14, 0));
        barcodeInner.setOpaque(true);
        barcodeInner.setBackground(new Color(0xFE, 0xFE, 0xE8));
        barcodeInner.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(new Color(0xFA, 0xCC, 0x15), 1, true),
                new EmptyBorder(14, 16, 14, 16)));

        barcodeIcon = new JLabel("\uD83D\uDD0D", SwingConstants.CENTER);
        barcodeIcon.setFont(new Font(Font.SANS_SERIF, Font.PLAIN, 24));
        barcodeIcon.setPreferredSize(new Dimension(40, 40));
        barcodeInner.add(barcodeIcon, BorderLayout.WEST);

        JPanel barcodeText = new JPanel();
        barcodeText.setOpaque(false);
        barcodeText.setLayout(new BoxLayout(barcodeText, BoxLayout.Y_AXIS));
        barcodeTitle = new JLabel("Scanning reads for barcode/linker prefixes...");
        barcodeTitle.setFont(Theme.FONT_BODY_BOLD);
        barcodeTitle.setForeground(Theme.INK_1);
        barcodeTitle.setAlignmentX(LEFT_ALIGNMENT);
        barcodeBody = new JLabel(" ");
        barcodeBody.setFont(Theme.FONT_SMALL);
        barcodeBody.setForeground(Theme.INK_3);
        barcodeBody.setAlignmentX(LEFT_ALIGNMENT);
        barcodeText.add(barcodeTitle);
        barcodeText.add(Box.createVerticalStrut(4));
        barcodeText.add(barcodeBody);

        barcodeBtnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 4));
        barcodeBtnRow.setOpaque(false);
        barcodeBtnRow.add(btnBarcodeDismiss);
        barcodeBtnRow.setVisible(false);
        barcodeBtnRow.setAlignmentX(LEFT_ALIGNMENT);
        barcodeText.add(Box.createVerticalStrut(8));
        barcodeText.add(barcodeBtnRow);

        barcodeInner.add(barcodeText, BorderLayout.CENTER);
        barcodeCard.row(barcodeInner);
        add(barcodeCard);

        btnBarcodeDismiss.addActionListener(e -> {
            barcodeCard.setVisible(false);
            revalidate();
        });

        // ---- Card 2: Primer Configuration ----
        Card primerCard = new Card("2 \u00B7 Primer Configuration");

        primerCard.row(new InfoBanner(InfoBanner.Kind.INFO, "Defaults",
                "Select your amplicon region and primers will auto-fill. " +
                "If your primers differ from the defaults, edit the fields below. " +
                "Select 'Custom' to enter arbitrary primers.")).gap(10);

        JPanel configGrid = new JPanel(new GridBagLayout());
        configGrid.setOpaque(false);
        GridBagConstraints gc = new GridBagConstraints();
        gc.insets = new Insets(4, 0, 4, 10);
        gc.anchor = GridBagConstraints.WEST;

        gc.gridx = 0; gc.gridy = 0;
        configGrid.add(tipLabel("Amplicon region:",
                "Select the amplicon region to auto-fill default primer sequences. Choose 'Custom' for non-standard primers."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
        ampliconCombo.setFont(Theme.FONT_BODY);
        configGrid.add(ampliconCombo, gc);

        gc.gridx = 0; gc.gridy = 1; gc.fill = GridBagConstraints.NONE; gc.weightx = 0;
        configGrid.add(tipLabel("Forward primer:",
                "5'-to-3' forward primer sequence. Supports IUPAC ambiguity codes (N, W, Y, etc.)."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
        fwdPrimerField.setFont(Theme.FONT_MONO);
        configGrid.add(fwdPrimerField, gc);

        gc.gridx = 0; gc.gridy = 2; gc.fill = GridBagConstraints.NONE; gc.weightx = 0;
        configGrid.add(tipLabel("Reverse primer:",
                "5'-to-3' reverse primer sequence. Ignored for single-end data."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
        revPrimerField.setFont(Theme.FONT_MONO);
        configGrid.add(revPrimerField, gc);

        gc.gridx = 0; gc.gridy = 3; gc.fill = GridBagConstraints.NONE; gc.weightx = 0;
        configGrid.add(tipLabel("Error rate:",
                "Maximum allowed error rate for primer matching (default 0.1 = 10%)."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.NONE;
        configGrid.add(errorRateSpinner, gc);

        gc.gridx = 0; gc.gridy = 4;
        configGrid.add(tipLabel("Times:",
                "Number of times to search for and remove adapters (default 1)."), gc);
        gc.gridx = 1;
        configGrid.add(timesSpinner, gc);

        gc.gridx = 0; gc.gridy = 5;
        configGrid.add(tipLabel("Overlap:",
                "Minimum overlap between the read and the primer for trimming. " +
                "Increase to reduce false-positive primer matches. Recommend 10\u201315 for most cases."), gc);
        gc.gridx = 1;
        configGrid.add(overlapSpinner, gc);

        gc.gridx = 0; gc.gridy = 6;
        configGrid.add(tipLabel("Min read length:",
                "Reads shorter than this after trimming will be discarded (default 50)."), gc);
        gc.gridx = 1;
        configGrid.add(minLenSpinner, gc);

        gc.gridx = 0; gc.gridy = 7;
        configGrid.add(tipLabel("CPU cores:",
                "Number of CPU cores for parallel processing (0 = all). Auto-detected from your system."), gc);
        gc.gridx = 1;
        configGrid.add(coresSpinner, gc);

        gc.gridx = 0; gc.gridy = 8; gc.gridwidth = 2;
        discardBox.setFont(Theme.FONT_BODY);
        discardBox.setOpaque(false);
        discardBox.setToolTipText("When enabled, reads where no primer was found are removed entirely.");
        configGrid.add(discardBox, gc);

        primerCard.row(configGrid);

        // System info
        JLabel sysInfo = new JLabel(
                "<html><span style='color:#64748B; font-size:11px;'>"
                + "\uD83D\uDDA5 System: <b>" + detectedCores + " CPU cores</b> detected \u2014 "
                + "using <b>" + recommendedCores + " cores</b> for Cutadapt "
                + "(1 reserved for system). Adjust below if needed."
                + "</span></html>");
        primerCard.row(sysInfo);
        add(primerCard);

        // ---- Card 3: Execute ----
        Card runCard = new Card("3 \u00B7 Execute Cutadapt");
        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        btnRow.setOpaque(false);
        btnRow.add(runBtn);
        btnRow.add(skipBtn);
        btnRow.add(stopBtn);
        statusLabel.setFont(Theme.FONT_BODY);
        btnRow.add(statusLabel);
        runCard.row(btnRow).gap(8);

        console.setPreferredSize(new Dimension(0, 180));
        runCard.row(console);
        add(runCard);

        // ---- Card 4: Command Preview ----
        Card previewCard = new Card("4 \u00B7 QIIME2 Command Preview");
        previewCard.row(new InfoBanner(InfoBanner.Kind.INFO, "Command",
                "The actual QIIME2 command that will be executed. " +
                "Updated live as you change parameters above.")).gap(6);
        cmdPreview.setEditable(false);
        cmdPreview.setFont(Theme.FONT_MONO);
        cmdPreview.setBackground(new Color(0x1E, 0x29, 0x3B));
        cmdPreview.setForeground(new Color(0xA5, 0xD6, 0xFF));
        cmdPreview.setBorder(BorderFactory.createEmptyBorder(10, 12, 10, 12));
        cmdPreview.setLineWrap(true);
        cmdPreview.setWrapStyleWord(true);
        JScrollPane previewScroll = new JScrollPane(cmdPreview);
        previewScroll.setPreferredSize(new Dimension(0, 80));
        previewScroll.setBorder(BorderFactory.createLineBorder(new Color(0x33, 0x44, 0x55)));
        previewCard.row(previewScroll);
        add(previewCard);

        // ---- Wiring ----
        runBtn.setEnabled(false);
        stopBtn.setEnabled(false);
        runBtn.addActionListener(e -> executeCutadapt());
        stopBtn.addActionListener(e -> {
            if (runningCmd != null) runningCmd.cancel();
        });

        // Skip button — marks step complete without running cutadapt
        skipBtn.addActionListener(e -> skipCutadapt());

        // Amplicon combo → auto-fill primers
        ampliconCombo.addActionListener(e -> {
            String sel = (String) ampliconCombo.getSelectedItem();
            if (sel != null && !"Custom".equals(sel)) {
                for (String[] pd : PRIMER_DEFAULTS) {
                    if (pd[0].equals(sel)) {
                        fwdPrimerField.setText(pd[1]);
                        revPrimerField.setText(pd[2]);
                        break;
                    }
                }
            }
            // Re-run barcode detection with updated amplicon length (affects overlap estimate)
            lastBarcodeResult = null;
            barcodeDetectionRunning = false;
            triggerBarcodeDetection();
        });

        // Live-update command preview when params change
        Runnable updatePreview = this::refreshCmdPreview;
        ampliconCombo.addActionListener(e2 -> updatePreview.run());
        fwdPrimerField.getDocument().addDocumentListener(new javax.swing.event.DocumentListener() {
            public void insertUpdate(javax.swing.event.DocumentEvent e) { updatePreview.run(); }
            public void removeUpdate(javax.swing.event.DocumentEvent e) { updatePreview.run(); }
            public void changedUpdate(javax.swing.event.DocumentEvent e) { updatePreview.run(); }
        });
        revPrimerField.getDocument().addDocumentListener(new javax.swing.event.DocumentListener() {
            public void insertUpdate(javax.swing.event.DocumentEvent e) { updatePreview.run(); }
            public void removeUpdate(javax.swing.event.DocumentEvent e) { updatePreview.run(); }
            public void changedUpdate(javax.swing.event.DocumentEvent e) { updatePreview.run(); }
        });
        minLenSpinner.addChangeListener(e2 -> updatePreview.run());
        errorRateSpinner.addChangeListener(e2 -> updatePreview.run());
        timesSpinner.addChangeListener(e2 -> updatePreview.run());
        overlapSpinner.addChangeListener(e2 -> updatePreview.run());
        coresSpinner.addChangeListener(e2 -> updatePreview.run());
        discardBox.addActionListener(e2 -> updatePreview.run());

        // Initialize with default primers
        ampliconCombo.setSelectedIndex(0);
    }

    @Override
    public void onShown() {
        // Auto-fill amplicon from wizard (set by ManifestPage or EasyModePage)
        String wizAmp = wizard.get("amplicon");
        if (wizAmp != null) {
            for (int i = 0; i < ampliconCombo.getItemCount(); i++) {
                if (wizAmp.equals(ampliconCombo.getItemAt(i))) {
                    ampliconCombo.setSelectedIndex(i);
                    break;
                }
            }
        }

        // Auto-fill demux from Import step
        String demuxQza = wizard.get("demux.qza");
        if (demuxQza != null && demuxPicker.isEmpty()) {
            demuxPicker.setPath(demuxQza);
        }
        refreshRunState();

        // Handle primer status from ManifestPage
        String primerStatus = wizard.get("primer.status");
        if ("removed".equals(primerStatus)) {
            // User said primers are already removed — enable skip, show guidance
            skipBtn.setEnabled(true);
            console.info("Primer status: You selected \u201CAlready removed\u201D in Step 1.");
            console.info("Click \u201CSkip Cutadapt \u2192\u201D to proceed to Denoising.");
            statusLabel.setText(
                "<html><span style='color:#0284C7'>\u2139 Primers already removed \u2014 "
                + "click Skip Cutadapt to proceed</span></html>");
            // Don't run barcode detection — user confirmed primers are removed
        } else if ("present".equals(primerStatus)) {
            // User said primers are present — disable skip, recommend running Cutadapt
            skipBtn.setEnabled(false);
            console.info("Primer status: You selected \u201CPresent in reads\u201D in Step 1.");
            console.info("Primers have been auto-filled for " + (wizAmp != null ? wizAmp : "your region") + ".");
            console.info("Verify the primer sequences below, then click \u201CRun Cutadapt\u201D.");
            statusLabel.setText(
                "<html><span style='color:#16A34A'>\u2713 Primers are present \u2014 "
                + "verify primers below and run Cutadapt</span></html>");
            // Still run barcode detection for informational purposes
            if (!demuxPicker.isEmpty() && lastBarcodeResult == null && !barcodeDetectionRunning) {
                triggerBarcodeDetection();
            }
        } else {
            // "auto-detect" or null → run barcode detection which controls skip button
            skipBtn.setEnabled(false);  // disabled until detection completes
            if (!demuxPicker.isEmpty() && lastBarcodeResult == null && !barcodeDetectionRunning) {
                triggerBarcodeDetection();
            }
        }
    }

    private void refreshRunState() {
        boolean hasDemux = !demuxPicker.isEmpty();
        runBtn.setEnabled(hasDemux);
    }

    // ==================================================================
    //  Skip Cutadapt — pass demux.qza through unchanged
    // ==================================================================
    private void skipCutadapt() {
        String demuxFile = demuxPicker.getPath();
        if (demuxFile == null || demuxFile.isEmpty()) {
            console.warn("Please select a demux .qza file first.");
            return;
        }

        // If user already declared primers are removed in ManifestPage, skip the confirm dialog
        boolean autoSkip = "removed".equals(wizard.get("primer.status"));
        int choice = autoSkip ? JOptionPane.YES_OPTION
                : JOptionPane.showConfirmDialog(this,
                "<html><body style='width:420px'>"
                + "<b>Skip primer removal?</b><br><br>"
                + "Only skip if you are certain primers have already been removed "
                + "from your reads (e.g., by the sequencing facility or a previous "
                + "processing step).<br><br>"
                + "The demux file will be passed directly to the Denoising step "
                + "without any trimming."
                + "</body></html>",
                "Skip Cutadapt?", JOptionPane.YES_NO_OPTION, JOptionPane.QUESTION_MESSAGE);

        if (choice == JOptionPane.YES_OPTION) {
            String amplicon = (String) ampliconCombo.getSelectedItem();
            wizard.put("amplicon", amplicon);

            console.info("Cutadapt skipped \u2014 primers assumed already removed.");
            console.info("Demux file passed directly to Denoising: " + demuxFile);
            statusLabel.setText(
                    "<html><span style='color:#D97706'>\u25CB Skipped (primers pre-removed)</span></html>");

            stepComplete = true;
            notifyStepCompletion();
        }
    }

    // ==================================================================
    //  Execute Cutadapt
    // ==================================================================
    private void executeCutadapt() {
        String fwdPrimer = fwdPrimerField.getText().trim();
        String revPrimer = revPrimerField.getText().trim();

        if (fwdPrimer.isEmpty() || revPrimer.isEmpty()) {
            console.err("Both forward and reverse primers are required.");
            return;
        }

        runBtn.setEnabled(false);
        skipBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        statusLabel.setText("<html><span style='color:#64748B'>Trimming primers\u2026</span></html>");
        console.clear();

        final String demuxFile = demuxPicker.getPath();
        final String outDir = wizard.get("output.dir",
                new File(demuxFile).getParent());
        final boolean paired = "paired".equals(wizard.get("read.type", "paired"));
        final int minLen = (int) minLenSpinner.getValue();
        final double errorRate = (double) errorRateSpinner.getValue();
        final int times = (int) timesSpinner.getValue();
        final int overlap = (int) overlapSpinner.getValue();
        final int cores = (int) coresSpinner.getValue();
        final boolean discard = discardBox.isSelected();
        final String amplicon = (String) ampliconCombo.getSelectedItem();

        new Thread(() -> {
            try {
                new File(outDir).mkdirs();
                String trimmedFile = outDir + File.separator + "trimmed.qza";

                QiimeCommand cmd;
                if (paired) {
                    cmd = new QiimeCommand("qiime cutadapt trim-paired")
                            .arg("--i-demultiplexed-sequences", demuxFile)
                            .arg("--p-front-f", fwdPrimer)
                            .arg("--p-front-r", revPrimer)
                            .arg("--p-error-rate", errorRate)
                            .arg("--p-times", times)
                            .arg("--p-overlap", overlap)
                            .arg("--p-minimum-length", minLen)
                            .arg("--p-cores", cores);
                } else {
                    cmd = new QiimeCommand("qiime cutadapt trim-single")
                            .arg("--i-demultiplexed-sequences", demuxFile)
                            .arg("--p-front", fwdPrimer)
                            .arg("--p-error-rate", errorRate)
                            .arg("--p-times", times)
                            .arg("--p-overlap", overlap)
                            .arg("--p-minimum-length", minLen)
                            .arg("--p-cores", cores);
                }

                if (discard) cmd.flag("--p-discard-untrimmed");
                cmd.arg("--o-trimmed-sequences", trimmedFile)
                   .flag("--verbose")
                   .workDir(outDir);

                runningCmd = cmd;
                int exit = cmd.run(console);

                if (exit == 0) {
                    wizard.put("demux.qza", trimmedFile);
                    wizard.put("output.dir", outDir);
                    wizard.put("amplicon", amplicon);

                    SwingUtilities.invokeLater(() -> {
                        statusLabel.setText("<html><span style='color:#16A34A'>\u2713 Primers removed</span></html>");
                        console.ok("Trimmed output: " + trimmedFile);
                        console.ok("Proceed to Quality Assessment to inspect quality and choose trim parameters.");
                        stepComplete = true;
                        notifyStepCompletion();
                    });
                } else {
                    SwingUtilities.invokeLater(() ->
                            statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Cutadapt failed</span></html>"));
                }

            } catch (Exception ex) {
                SwingUtilities.invokeLater(() -> {
                    console.err("Error: " + ex.getMessage());
                    statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Error</span></html>");
                });
            } finally {
                SwingUtilities.invokeLater(() -> {
                    runBtn.setEnabled(true);
                    stopBtn.setEnabled(false);
                });
            }
        }).start();
    }

    private void refreshCmdPreview() {
        String fwd = fwdPrimerField.getText().trim();
        String rev = revPrimerField.getText().trim();
        int minLen = (int) minLenSpinner.getValue();
        double errorRate = (double) errorRateSpinner.getValue();
        int times = (int) timesSpinner.getValue();
        int overlap = (int) overlapSpinner.getValue();
        int cores = (int) coresSpinner.getValue();
        boolean discard = discardBox.isSelected();
        boolean paired = "paired".equals(wizard.get("read.type", "paired"));
        String demux = demuxPicker.isEmpty() ? "<demux.qza>" : demuxPicker.getPath();
        String out = wizard.get("output.dir", ".") + File.separator + "trimmed.qza";

        StringBuilder sb = new StringBuilder();
        if (paired) {
            sb.append("qiime cutadapt trim-paired \\\n");
            sb.append("  --i-demultiplexed-sequences ").append(demux).append(" \\\n");
            sb.append("  --p-front-f ").append(fwd.isEmpty() ? "<forward_primer>" : fwd).append(" \\\n");
            sb.append("  --p-front-r ").append(rev.isEmpty() ? "<reverse_primer>" : rev).append(" \\\n");
        } else {
            sb.append("qiime cutadapt trim-single \\\n");
            sb.append("  --i-demultiplexed-sequences ").append(demux).append(" \\\n");
            sb.append("  --p-front ").append(fwd.isEmpty() ? "<forward_primer>" : fwd).append(" \\\n");
        }
        sb.append("  --p-error-rate ").append(errorRate).append(" \\\n");
        sb.append("  --p-times ").append(times).append(" \\\n");
        sb.append("  --p-overlap ").append(overlap).append(" \\\n");
        sb.append("  --p-minimum-length ").append(minLen).append(" \\\n");
        sb.append("  --p-cores ").append(cores).append(" \\\n");
        if (discard) sb.append("  --p-discard-untrimmed \\\n");
        sb.append("  --o-trimmed-sequences ").append(out).append(" \\\n");
        sb.append("  --verbose");
        cmdPreview.setText(sb.toString());
        cmdPreview.setCaretPosition(0);
    }

    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }

    private JLabel tipLabel(String text, String tooltip) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_BODY);
        l.setForeground(Theme.INK_2);
        l.setToolTipText(tooltip);
        l.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        return l;
    }

    private static JSpinner spinner(int value, int min, int max, int step) {
        JSpinner sp = new JSpinner(new SpinnerNumberModel(value, min, max, step));
        sp.setFont(new Font(Font.SANS_SERIF, Font.PLAIN, 13));
        return sp;
    }

    private static JSpinner spinnerDouble(double value, double min, double max, double step) {
        JSpinner sp = new JSpinner(new SpinnerNumberModel(value, min, max, step));
        sp.setFont(new Font(Font.SANS_SERIF, Font.PLAIN, 13));
        return sp;
    }

    // ==================================================================
    //  Barcode / Linker Auto-Detection (runs in background)
    //  This is the SINGLE detection system — no separate "Detect Primers"
    // ==================================================================

    /** Trigger barcode detection in a background thread. */
    private void triggerBarcodeDetection() {
        if (barcodeDetectionRunning || demuxPicker.isEmpty()) return;
        final String qzaPath = demuxPicker.getPath();
        if (qzaPath == null || !new File(qzaPath).isFile()) return;

        barcodeDetectionRunning = true;
        lastBarcodeResult = null;

        SwingUtilities.invokeLater(() -> {
            barcodeIcon.setText("\uD83D\uDD0D");
            barcodeTitle.setText("Scanning reads for barcodes, linkers, and primers...");
            barcodeBody.setText("<html>Analyzing FASTQ reads inside the .qza artifact to check for " +
                    "non-biological sequence (barcodes, linkers, primers) at the start of your reads.</html>");
            barcodeBtnRow.setVisible(false);
            barcodeCard.setVisible(true);
            revalidate();
            repaint();
        });

        new Thread(() -> {
            try {
                BarcodeDetector.DetectionResult result = BarcodeDetector.analyze(qzaPath, getAmpliconLength());
                lastBarcodeResult = result;

                SwingUtilities.invokeLater(() -> {
                    if (result.detected) {
                        showBarcodeWarning(result);
                    } else {
                        showBarcodeClean(result);
                    }
                    barcodeDetectionRunning = false;
                });
            } catch (Exception e) {
                SwingUtilities.invokeLater(() -> {
                    barcodeCard.setVisible(false);
                    barcodeDetectionRunning = false;
                    // If detection fails, enable skip so user isn't stuck
                    skipBtn.setEnabled(true);
                    revalidate();
                });
            }
        }, "CutadaptBarcodeDetector").start();
    }

    /** Show warning card when barcode/linker IS detected → DISABLE Skip. */
    private void showBarcodeWarning(BarcodeDetector.DetectionResult r) {
        barcodeIcon.setText("\u26A0");
        barcodeTitle.setText("Barcode / Primer Detected \u2014 Run Cutadapt Required");

        StringBuilder html = new StringBuilder("<html><body style='width:640px'>");
        html.append("<b>EzMAP v2.0 found non-biological sequence at the start of your reads.</b><br><br>");

        html.append("<b>Forward reads:</b> ").append(escHtml(r.forwardDetail));
        if (r.avgReadLenF > 0) {
            html.append(" (avg length: ").append(r.avgReadLenF).append("bp)");
        }
        html.append("<br>");

        if (r.hasPairedEnd) {
            html.append("<b>Reverse reads:</b> ").append(escHtml(r.reverseDetail));
            if (r.avgReadLenR > 0) {
                html.append(" (avg length: ").append(r.avgReadLenR).append("bp)");
            }
            html.append("<br><br>");
        }

        html.append("<span style='color:#0369A1'><b>Good news:</b> Cutadapt handles this automatically!</span> ")
            .append("The <code>--p-front</code> parameter finds your primer sequence at any position in the read ")
            .append("and removes <b>everything before and including it</b> \u2014 so barcodes, linkers, and primers ")
            .append("all get stripped in one step.<br><br>");

        html.append("<b>Action:</b> Make sure the correct primer sequences are entered below, ")
            .append("then click <b>Run Cutadapt</b>. Do NOT skip this step \u2014 these prefixes will ")
            .append("cause denoising failures if left in the reads.");

        // Overlap warning for paired-end
        if (r.hasPairedEnd) {
            int effectiveF = r.avgReadLenF - r.suggestedTrimLeftF;
            int effectiveR = r.avgReadLenR - r.suggestedTrimLeftR;
            int ampliconLen = getAmpliconLength();
            String regionName = getAmpliconRegionName();
            int overlap = effectiveF + effectiveR - ampliconLen;
            if (overlap < 40) {
                html.append("<br><br><span style='color:#B91C1C'><b>\u26A0 Tight overlap notice:</b> ")
                    .append("After removing the prefixes (~").append(r.suggestedTrimLeftF)
                    .append("bp fwd, ~").append(r.suggestedTrimLeftR)
                    .append("bp rev), estimated overlap for ").append(regionName)
                    .append(" is only ~")
                    .append(Math.max(0, overlap)).append("bp. ")
                    .append("Use truncate = 0 (no truncation) in the Denoising step to preserve ")
                    .append("maximum overlap.</span>");
            }
        }

        html.append("</body></html>");
        barcodeBody.setText(html.toString());
        barcodeBtnRow.setVisible(true);
        barcodeCard.setVisible(true);

        // DISABLE Skip — barcodes/primers are present, user must run Cutadapt
        skipBtn.setEnabled(false);
        statusLabel.setText(
            "<html><span style='color:#DC2626'>\u26A0 Primers/barcodes detected \u2014 "
            + "run Cutadapt to remove them</span></html>");

        revalidate();
        repaint();
    }

    /** Show brief green confirmation when reads are clean → ENABLE Skip. */
    private void showBarcodeClean(BarcodeDetector.DetectionResult r) {
        barcodeIcon.setText("\u2705");
        barcodeTitle.setText("Reads Look Clean \u2014 No Barcode/Linker Detected");

        StringBuilder html = new StringBuilder("<html><body style='width:640px'>");
        html.append("No non-biological barcode or linker prefix was detected. ");
        html.append("Your reads appear to start directly with biological sequence.");
        if (r.avgReadLenF > 0) {
            html.append("<br>Average read lengths: forward = ").append(r.avgReadLenF).append("bp");
            if (r.hasPairedEnd && r.avgReadLenR > 0) {
                html.append(", reverse = ").append(r.avgReadLenR).append("bp");
            }
            html.append(".");
        }
        html.append("<br><br>You may <b>Skip Cutadapt</b> if primers were already removed, ")
            .append("or <b>Run Cutadapt</b> if you want to trim primers.");
        html.append("</body></html>");

        barcodeBody.setText(html.toString());
        barcodeBtnRow.setVisible(false);
        barcodeCard.setVisible(true);

        // ENABLE Skip — reads are clean
        skipBtn.setEnabled(true);
        statusLabel.setText(
            "<html><span style='color:#0284C7'>\u2139 No barcodes detected \u2014 "
            + "you may skip or run Cutadapt</span></html>");

        // Auto-hide clean result after 10 seconds
        Timer hideTimer = new Timer(10000, e -> {
            barcodeCard.setVisible(false);
            revalidate();
        });
        hideTimer.setRepeats(false);
        hideTimer.start();

        revalidate();
        repaint();
    }

    /** Get expected amplicon length based on selected region. */
    private int getAmpliconLength() {
        String sel = (String) ampliconCombo.getSelectedItem();
        if (sel == null) return 460;
        switch (sel) {
            case "16S-V4":   return 253;
            case "16S-V3V4": return 460;
            case "ITS1":     return 300;  // highly variable
            case "ITS2":     return 350;  // highly variable
            default:         return 400;
        }
    }

    /** Get display name for the selected amplicon region. */
    private String getAmpliconRegionName() {
        String sel = (String) ampliconCombo.getSelectedItem();
        if (sel == null) return "the amplicon";
        switch (sel) {
            case "16S-V4":   return "V4";
            case "16S-V3V4": return "V3-V4";
            case "ITS1":     return "ITS1";
            case "ITS2":     return "ITS2";
            default:         return "the amplicon";
        }
    }

    private static String escHtml(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
