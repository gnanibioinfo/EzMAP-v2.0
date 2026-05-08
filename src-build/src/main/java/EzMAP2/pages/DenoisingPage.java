package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import java.awt.*;
import java.io.File;
import javax.swing.border.EmptyBorder;

/**
 * Expert Mode — Step 4: Denoising / OTU Clustering.
 *
 * Three methods:
 *   1. DADA2 — ASV-based (paired or single-end)
 *   2. Deblur — ASV-based
 *   3. VSEARCH — OTU clustering (97% identity, USEARCH-compatible)
 *
 * Also provides a paired→single-end override toggle for DADA2,
 * useful when paired-end merging fails (e.g. pre-processed legacy data).
 */
public class DenoisingPage extends BasePage {

    private final WizardController wizard;
    private boolean stepComplete = false;

    @Override public boolean isStepComplete() { return stepComplete; }

    // Input
    private final DirectoryPicker demuxPicker;

    // Read type override
    private final JCheckBox cbForceSingle = new JCheckBox(
            "Use forward reads only (single-end mode)");

    // Denoiser selection
    private final JRadioButton rbDada2   = new JRadioButton("DADA2 (recommended)", true);
    private final JRadioButton rbDeblur  = new JRadioButton("Deblur");
    private final JRadioButton rbVsearch = new JRadioButton("VSEARCH (OTU clustering)");

    // DADA2 parameters
    private final JSpinner spTrimLeftF  = spinner(0, 0, 100, 1);
    private final JSpinner spTruncF     = spinner(240, 0, 500, 10);
    private final JSpinner spTrimLeftR  = spinner(0, 0, 100, 1);
    private final JSpinner spTruncR     = spinner(200, 0, 500, 10);
    private final JComboBox<String> cbChimera = new JComboBox<>(
            new String[]{"consensus", "pooled", "none"});
    private final JSpinner spThreads    = spinner(4, 1, 64, 1);
    private final JSpinner spMaxEEF     = spinnerDouble(2.0, 0.0, 100.0, 0.5);
    private final JSpinner spMaxEER     = spinnerDouble(2.0, 0.0, 100.0, 0.5);
    private final JSpinner spTruncQ     = spinner(2, 0, 40, 1);
    private final JSpinner spMinFold    = spinnerDouble(1.0, 0.1, 100.0, 0.5);

    // Labels for reverse params (hidden in single-end mode)
    private final JLabel lblTrimLeftR;
    private final JLabel lblTruncR;
    private final JLabel lblMaxEER;

    // Deblur parameters
    private final JSpinner spDeblurTrim = spinner(250, 50, 500, 10);
    private final JSpinner spDeblurJobs = spinner(4, 1, 64, 1);
    private final JSpinner spDeblurMinReads = spinner(10, 1, 1000, 1);
    private final JSpinner spDeblurMinFold  = spinnerDouble(2.0, 0.1, 100.0, 0.5);

    // VSEARCH parameters
    private final JSpinner spVsPercId     = spinnerDouble(0.97, 0.80, 1.00, 0.01);
    private final JSpinner spVsMinOverlap = spinner(10, 1, 100, 1);
    private final JSpinner spVsMinQual    = spinner(20, 0, 40, 1);
    private final JSpinner spVsThreads    = spinner(4, 1, 64, 1);
    private final JSpinner spVsMinLen     = spinner(100, 50, 500, 10);
    private final JCheckBox cbVsStagger   = new JCheckBox("Allow merge stagger", true);
    private final JComboBox<String> cbVsChimera = new JComboBox<>(
            new String[]{"de novo (uchime)", "none"});

    // Panels (toggled by denoiser selection)
    private final JPanel dada2Panel  = new JPanel(new GridLayout(0, 2, 10, 8));
    private final JPanel deblurPanel = new JPanel(new GridLayout(0, 2, 10, 8));
    private final JPanel vsearchPanel = new JPanel(new GridLayout(0, 2, 10, 8));
    private final InfoBanner dada2Tip;

    // Controls
    private final PrimaryButton runBtn = new PrimaryButton("Run Denoising  \u2192");
    private final OutlineButton stopBtn = new OutlineButton("Stop");
    private final JLabel statusLabel = new JLabel(" ");
    private final LogConsole console = new LogConsole();
    private final JTextArea cmdPreview = new JTextArea(4, 60);

    private volatile QiimeCommand runningCmd;

    // Smart trim defaults per amplicon region: {amplicon, fwdTrunc, revTrunc, deblurTrim}
    private static final Object[][] SMART_TRIM = {
        {"16S-V3V4", 260, 220, 250},   // ~460bp amplicon
        {"16S-V4",   230, 200, 230},   // ~253bp amplicon
        {"ITS1",     0,   0,   250},    // variable length — 0 means no truncation
        {"ITS2",     0,   0,   250},    // variable length
    };

    private boolean smartTrimApplied = false;

    // Barcode/linker auto-detection card
    private final Card detectionCard;
    private final JLabel detectionIcon;
    private final JLabel detectionTitle;
    private final JLabel detectionBody;
    private final JPanel detectionBtnRow;
    private final PrimaryButton btnApplyDetection = new PrimaryButton("Apply Suggestions");
    private final OutlineButton btnDismissDetection = new OutlineButton("Dismiss");
    private volatile boolean detectionRunning = false;
    private volatile BarcodeDetector.DetectionResult lastDetection = null;

    public DenoisingPage(WizardController wizard) {
        super("Expert Mode — Step 5: Denoising / OTU Clustering",
              "Denoise your sequences (DADA2/Deblur → ASVs) or cluster into OTUs (VSEARCH → 97% OTUs). " +
              "Choose based on your study design and the upstream pipeline used.");
        this.wizard = wizard;

        // ---- Card 1: Quality Plot Reference Guide ----
        Card guideCard = new Card("1 \u00B7 Quality Plot Reference");
        guideCard.row(guideLabel(
                "<html><body style='width:680px'>" +
                "<b>How to read the quality plot</b> (from the previous step's .qzv):<br><br>" +
                "\u2022 X-axis = base position in read, Y-axis = quality score (Q).<br>" +
                "\u2022 <span style='color:#16A34A'><b>Good:</b></span> median Q \u2265 30. Reads are accurate.<br>" +
                "\u2022 <span style='color:#CA8A04'><b>Acceptable:</b></span> median Q 20\u201330. Some errors but usually OK.<br>" +
                "\u2022 <span style='color:#DC2626'><b>Poor:</b></span> median Q &lt; 20. Truncate before this point.<br><br>" +
                "<b>How to choose trim/truncate values below:</b><br>" +
                "\u2022 <b>Trim left:</b> bases to remove at the start (usually 0 if Cutadapt was used).<br>" +
                "\u2022 <b>Truncate:</b> cut reads where quality drops below Q20\u201325. " +
                "Forward reads usually keep quality longer than reverse.<br>" +
                "\u2022 <b>Overlap:</b> for paired-end, fwd + rev truncate lengths must exceed your amplicon " +
                "length by \u226520bp for DADA2 to merge reads. " +
                "E.g., 16S V3-V4 (~460bp): fwd 260 + rev 220 = 480 \u2212 460 = 20bp overlap \u2714" +
                "</body></html>"));
        add(guideCard);

        // ---- Card 2: Input + Read Type Override ----
        Card inputCard = new Card("2 \u00B7 Input & Read Type");
        inputCard.row(caption("Demux .qza file:"));
        demuxPicker = new DirectoryPicker("Select demux .qza",
                f -> { refreshRunState(); triggerBarcodeDetection(); }, true);
        inputCard.row(demuxPicker);

        inputCard.gap(8);
        cbForceSingle.setOpaque(false);
        cbForceSingle.setFont(Theme.FONT_BODY);
        cbForceSingle.setToolTipText(
            "<html>Override paired-end detection and use only forward reads.<br>" +
            "Useful when paired-end merging fails (e.g. pre-processed legacy data,<br>" +
            "reads too short to overlap, or data from USEARCH/QIIME 1 studies).</html>");
        cbForceSingle.addActionListener(e -> {
            togglePairedFields();
            refreshCmdPreview();
        });
        inputCard.row(cbForceSingle);
        inputCard.row(new InfoBanner(InfoBanner.Kind.INFO, "Single-End Mode",
                "<html>Enable this if DADA2 paired-end merging produces near-zero reads. " +
                "Common with legacy datasets where reads were pre-processed by USEARCH/QIIME 1. " +
                "Single-end mode uses only forward reads and skips the merging step.</html>"));
        add(inputCard);

        // ---- Barcode/Linker Auto-Detection Card (initially hidden) ----
        detectionCard = new Card(null);
        detectionCard.setVisible(false);

        // Build the card content manually for a richer layout
        JPanel detectionInner = new JPanel(new BorderLayout(14, 0));
        detectionInner.setOpaque(true);
        detectionInner.setBackground(new Color(0xFE, 0xFE, 0xE8));
        detectionInner.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(new Color(0xFA, 0xCC, 0x15), 1, true),
                new EmptyBorder(14, 16, 14, 16)));

        // Icon
        detectionIcon = new JLabel("\uD83D\uDD0D", SwingConstants.CENTER);  // magnifying glass
        detectionIcon.setFont(new Font(Font.SANS_SERIF, Font.PLAIN, 24));
        detectionIcon.setPreferredSize(new Dimension(40, 40));
        detectionInner.add(detectionIcon, BorderLayout.WEST);

        // Text column
        JPanel detectionText = new JPanel();
        detectionText.setOpaque(false);
        detectionText.setLayout(new BoxLayout(detectionText, BoxLayout.Y_AXIS));
        detectionTitle = new JLabel("Scanning reads for barcode/linker prefixes...");
        detectionTitle.setFont(Theme.FONT_BODY_BOLD);
        detectionTitle.setForeground(Theme.INK_1);
        detectionTitle.setAlignmentX(LEFT_ALIGNMENT);
        detectionBody = new JLabel(" ");
        detectionBody.setFont(Theme.FONT_SMALL);
        detectionBody.setForeground(Theme.INK_3);
        detectionBody.setAlignmentX(LEFT_ALIGNMENT);
        detectionText.add(detectionTitle);
        detectionText.add(Box.createVerticalStrut(4));
        detectionText.add(detectionBody);

        // Buttons row (initially hidden until results arrive)
        detectionBtnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 4));
        detectionBtnRow.setOpaque(false);
        detectionBtnRow.add(btnApplyDetection);
        detectionBtnRow.add(btnDismissDetection);
        detectionBtnRow.setVisible(false);
        detectionBtnRow.setAlignmentX(LEFT_ALIGNMENT);
        detectionText.add(Box.createVerticalStrut(8));
        detectionText.add(detectionBtnRow);

        detectionInner.add(detectionText, BorderLayout.CENTER);
        detectionCard.row(detectionInner);
        add(detectionCard);

        // Wire Apply/Dismiss buttons
        btnApplyDetection.addActionListener(e -> applyDetectionResults());
        btnDismissDetection.addActionListener(e -> {
            detectionCard.setVisible(false);
            revalidate();
        });

        // ---- Card 3: Denoiser selection ----
        Card denoiserCard = new Card("3 \u00B7 Denoiser & Parameters");

        JPanel denoiserRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 16, 4));
        denoiserRow.setOpaque(false);
        ButtonGroup bg = new ButtonGroup();
        bg.add(rbDada2);
        bg.add(rbDeblur);
        bg.add(rbVsearch);
        denoiserRow.add(rbDada2);
        denoiserRow.add(rbDeblur);
        denoiserRow.add(rbVsearch);
        denoiserCard.row(denoiserRow).gap(8);

        // DADA2 panel
        dada2Panel.setOpaque(false);
        dada2Panel.add(tipLabel("Forward trim left:",
                "Number of bases to remove from the start of forward reads. Set to 0 if primers were already removed by Cutadapt."));
        dada2Panel.add(spTrimLeftF);
        dada2Panel.add(tipLabel("Forward truncate:",
                "Truncate forward reads at this position. Set to 0 for no truncation (keeps full length). Choose where quality drops below Q25 in the quality plot."));
        dada2Panel.add(spTruncF);
        lblTrimLeftR = tipLabel("Reverse trim left:",
                "Number of bases to remove from the start of reverse reads. Set to 0 if primers were already removed by Cutadapt.");
        dada2Panel.add(lblTrimLeftR);
        dada2Panel.add(spTrimLeftR);
        lblTruncR = tipLabel("Reverse truncate:",
                "Truncate reverse reads at this position. Set to 0 for no truncation. Reverse reads typically lose quality faster than forward reads.");
        dada2Panel.add(lblTruncR);
        dada2Panel.add(spTruncR);
        dada2Panel.add(tipLabel("Max expected errors (fwd):",
                "Forward reads with more than this many expected errors will be discarded. Default 2.0. Lower values (e.g. 1.0) = stricter filtering, fewer but higher-quality reads."));
        dada2Panel.add(spMaxEEF);
        lblMaxEER = tipLabel("Max expected errors (rev):",
                "Reverse reads with more than this many expected errors will be discarded. Default 2.0. Reverse reads often have lower quality, so you may keep this at 2.0 or increase slightly.");
        dada2Panel.add(lblMaxEER);
        dada2Panel.add(spMaxEER);
        dada2Panel.add(tipLabel("Trunc quality (--trunc-q):",
                "Truncate reads at the first base with quality score <= this value. Default 2 (essentially off). Set to 15-20 for aggressive quality trimming as an alternative to fixed truncation."));
        dada2Panel.add(spTruncQ);
        dada2Panel.add(tipLabel("Chimera method:",
                "<html><b>consensus</b> (default): Checks each sample independently, then removes chimeras found in enough samples. Balanced and recommended for most datasets.<br><br>"
                + "<b>pooled</b>: Pools all samples together for chimera detection. More sensitive — catches rare chimeras missed by consensus, but may produce false positives in diverse communities. Use for low-biomass or highly diverse samples.<br><br>"
                + "<b>none</b>: Skips chimera removal entirely. Only use if you have already removed chimeras externally or are troubleshooting.</html>"));
        dada2Panel.add(cbChimera);
        dada2Panel.add(tipLabel("Min fold parent abundance:",
                "Minimum fold-difference between a potential chimera's parent sequences and the chimera for removal. Default 1.0. Higher values (e.g. 2.0) = more conservative chimera calling (fewer removed). Only applies when chimera method is not 'none'."));
        dada2Panel.add(spMinFold);
        dada2Panel.add(tipLabel("Threads:",
                "Number of CPU threads for DADA2. More threads = faster processing. Set to the number of available CPU cores for best performance."));
        dada2Panel.add(spThreads);
        denoiserCard.row(dada2Panel);

        // Deblur panel (hidden initially)
        deblurPanel.setOpaque(false);
        deblurPanel.add(tipLabel("Trim length:",
                "All reads are truncated to this length. Reads shorter than this are discarded. Choose based on your amplicon length and quality profile."));
        deblurPanel.add(spDeblurTrim);
        deblurPanel.add(tipLabel("Min reads:",
                "Minimum number of reads required for a sample to be included. Default 10. Increase to filter out very low-coverage samples."));
        deblurPanel.add(spDeblurMinReads);
        deblurPanel.add(tipLabel("Min fold parent abundance:",
                "Minimum fold-difference for chimera detection in Deblur. Default 2.0. Higher = more conservative chimera removal."));
        deblurPanel.add(spDeblurMinFold);
        deblurPanel.add(tipLabel("Parallel jobs:",
                "Number of parallel jobs for Deblur. More jobs = faster processing."));
        deblurPanel.add(spDeblurJobs);
        deblurPanel.setVisible(false);
        denoiserCard.row(deblurPanel);

        // VSEARCH panel (hidden initially)
        vsearchPanel.setOpaque(false);
        vsearchPanel.add(tipLabel("Percent identity:",
                "<html>Sequence similarity threshold for OTU clustering. Default <b>0.97</b> (97%) " +
                "matches traditional USEARCH/QIIME 1 OTU definitions. Use 0.99 for finer resolution.</html>"));
        vsearchPanel.add(spVsPercId);
        vsearchPanel.add(tipLabel("Min overlap length:",
                "Minimum overlap (bp) required to merge paired-end reads. Default 10. " +
                "VSEARCH merge-pairs is more lenient than DADA2, often succeeding where DADA2 fails."));
        vsearchPanel.add(spVsMinOverlap);
        vsearchPanel.add(tipLabel("Min quality score:",
                "Reads with average quality below this threshold are discarded during quality filtering. Default 20."));
        vsearchPanel.add(spVsMinQual);
        vsearchPanel.add(tipLabel("Min merged length:",
                "Minimum length of merged/filtered reads to keep. Reads shorter than this are discarded. Default 100."));
        vsearchPanel.add(spVsMinLen);
        vsearchPanel.add(tipLabel("Allow merge stagger:",
                "Allow merging of staggered read pairs (where reverse read extends past the start of forward). " +
                "Enable for variable-length amplicons or pre-trimmed data."));
        cbVsStagger.setOpaque(false);
        cbVsStagger.setFont(Theme.FONT_BODY);
        vsearchPanel.add(cbVsStagger);
        vsearchPanel.add(tipLabel("Chimera removal:",
                "<html><b>de novo (uchime)</b>: VSEARCH's UCHIME de novo chimera detection — " +
                "same algorithm as USEARCH. Recommended.<br>" +
                "<b>none</b>: Skip chimera removal.</html>"));
        vsearchPanel.add(cbVsChimera);
        vsearchPanel.add(tipLabel("Threads:",
                "Number of CPU threads. More threads = faster processing."));
        vsearchPanel.add(spVsThreads);
        vsearchPanel.setVisible(false);
        denoiserCard.row(vsearchPanel);

        denoiserCard.gap(8);
        dada2Tip = new InfoBanner(InfoBanner.Kind.INFO, "Tip",
                "For paired-end data, set forward truncate where forward read quality drops " +
                "below Q25, and reverse truncate where reverse quality drops. " +
                "Ensure forward + reverse truncate length exceeds your amplicon length by \u226520bp " +
                "for sufficient overlap.");
        denoiserCard.row(dada2Tip);
        add(denoiserCard);

        // ---- Card 4: Run ----
        Card runCard = new Card("4 \u00B7 Execute");
        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        btnRow.setOpaque(false);
        btnRow.add(runBtn);
        btnRow.add(stopBtn);
        statusLabel.setFont(Theme.FONT_BODY);
        btnRow.add(statusLabel);
        runCard.row(btnRow).gap(8);

        console.setPreferredSize(new Dimension(0, 200));
        runCard.row(console);
        add(runCard);

        // ---- Card 5: Command Preview ----
        Card previewCard = new Card("5 \u00B7 Command Preview");
        previewCard.row(new InfoBanner(InfoBanner.Kind.INFO, "Live Preview",
                "Shows the actual QIIME2 command(s) that will execute. " +
                "Updates automatically as you change parameters.")).gap(6);
        cmdPreview.setEditable(false);
        cmdPreview.setFont(Theme.FONT_MONO);
        cmdPreview.setBackground(new Color(0x1E, 0x29, 0x3B));
        cmdPreview.setForeground(new Color(0xA5, 0xD6, 0xFF));
        cmdPreview.setBorder(BorderFactory.createEmptyBorder(10, 12, 10, 12));
        cmdPreview.setLineWrap(true);
        cmdPreview.setWrapStyleWord(true);
        JScrollPane previewScroll = new JScrollPane(cmdPreview);
        previewScroll.setPreferredSize(new Dimension(0, 140));
        previewScroll.setBorder(BorderFactory.createLineBorder(new Color(0x33, 0x44, 0x55)));
        previewCard.row(previewScroll);
        add(previewCard);

        // ---- Wiring ----
        runBtn.setEnabled(false);
        stopBtn.setEnabled(false);

        rbDada2.addActionListener(e -> { toggleDenoiser(); refreshCmdPreview(); });
        rbDeblur.addActionListener(e -> { toggleDenoiser(); refreshCmdPreview(); });
        rbVsearch.addActionListener(e -> { toggleDenoiser(); refreshCmdPreview(); });
        runBtn.addActionListener(e -> executeDenoising());
        stopBtn.addActionListener(e -> {
            if (runningCmd != null) runningCmd.cancel();
        });

        // Live-update preview when params change
        for (JSpinner sp : new JSpinner[]{spTrimLeftF, spTruncF, spTrimLeftR, spTruncR,
                spThreads, spMaxEEF, spMaxEER, spTruncQ, spMinFold,
                spDeblurTrim, spDeblurJobs, spDeblurMinReads, spDeblurMinFold,
                spVsPercId, spVsMinOverlap, spVsMinQual, spVsThreads, spVsMinLen}) {
            sp.addChangeListener(e2 -> refreshCmdPreview());
        }
        cbChimera.addActionListener(e2 -> refreshCmdPreview());
        cbVsChimera.addActionListener(e2 -> refreshCmdPreview());
        cbVsStagger.addActionListener(e2 -> refreshCmdPreview());

        // Style
        for (JRadioButton rb : new JRadioButton[]{rbDada2, rbDeblur, rbVsearch}) {
            rb.setFont(Theme.FONT_BODY);
            rb.setOpaque(false);
        }
        cbChimera.setFont(Theme.FONT_BODY);
        cbVsChimera.setFont(Theme.FONT_BODY);
    }

    @Override
    public void onShown() {
        String demuxQza = wizard.get("demux.qza");
        if (demuxQza != null && demuxPicker.isEmpty()) {
            demuxPicker.setPath(demuxQza);
        }

        // Smart trim auto-fill based on amplicon region (from Cutadapt step)
        if (!smartTrimApplied) {
            String amplicon = wizard.get("amplicon");
            if (amplicon != null) {
                for (Object[] row : SMART_TRIM) {
                    if (row[0].equals(amplicon)) {
                        int fwdTrunc = (int) row[1];
                        int revTrunc = (int) row[2];
                        int deblurTr = (int) row[3];

                        boolean isIts = amplicon.startsWith("ITS");

                        // DADA2 params
                        spTrimLeftF.setValue(0);
                        spTrimLeftR.setValue(0);
                        if (fwdTrunc > 0) spTruncF.setValue(fwdTrunc);
                        if (revTrunc > 0) spTruncR.setValue(revTrunc);
                        // Deblur params
                        spDeblurTrim.setValue(deblurTr);

                        smartTrimApplied = true;

                        // Show smart trim alert
                        String msg;
                        if (isIts) {
                            msg = "Amplicon region: " + amplicon + "\n\n"
                                + "ITS regions have variable length, so no truncation is applied by default.\n"
                                + "Review your quality plot and set truncation values manually if needed.\n\n"
                                + "Trim left is set to 0 (primers already removed by Cutadapt).";
                        } else {
                            msg = "Amplicon region: " + amplicon + "\n\n"
                                + "EzMAP v2 Smart Trim has pre-filled suggested values:\n"
                                + "  \u2022 Forward truncate: " + fwdTrunc + "\n"
                                + "  \u2022 Reverse truncate: " + revTrunc + "\n"
                                + "  \u2022 Trim left: 0 (primers removed by Cutadapt)\n\n"
                                + "These are based on typical quality profiles for " + amplicon + ".\n"
                                + "Review your quality plot and adjust if needed.";
                        }

                        JOptionPane.showMessageDialog(this, msg,
                                "EzMAP v2 \u2014 Smart Trim Suggestion",
                                JOptionPane.INFORMATION_MESSAGE);
                        break;
                    }
                }
            }
        }

        refreshRunState();
        refreshCmdPreview();

        // Auto-detect barcode/linker if demux file is available
        if (!demuxPicker.isEmpty() && lastDetection == null && !detectionRunning) {
            triggerBarcodeDetection();
        }
    }

    /** Whether the effective read type is single-end (either detected or overridden). */
    private boolean isEffectivelySingle() {
        return cbForceSingle.isSelected()
                || "single".equals(wizard.get("read.type", "paired"));
    }

    private void refreshCmdPreview() {
        String demux = demuxPicker.isEmpty() ? "<demux.qza>" : demuxPicker.getPath();
        String outDir = wizard.get("output.dir", ".");
        boolean paired = !isEffectivelySingle();

        StringBuilder sb = new StringBuilder();

        if (rbDada2.isSelected()) {
            // --- DADA2 preview ---
            if (paired) {
                sb.append("qiime dada2 denoise-paired \\\n");
                sb.append("  --i-demultiplexed-seqs ").append(demux).append(" \\\n");
                sb.append("  --p-trim-left-f ").append(spTrimLeftF.getValue()).append(" \\\n");
                sb.append("  --p-trim-left-r ").append(spTrimLeftR.getValue()).append(" \\\n");
                sb.append("  --p-trunc-len-f ").append(spTruncF.getValue()).append(" \\\n");
                sb.append("  --p-trunc-len-r ").append(spTruncR.getValue()).append(" \\\n");
                sb.append("  --p-max-ee-f ").append(spMaxEEF.getValue()).append(" \\\n");
                sb.append("  --p-max-ee-r ").append(spMaxEER.getValue()).append(" \\\n");
            } else {
                sb.append("qiime dada2 denoise-single \\\n");
                sb.append("  --i-demultiplexed-seqs ").append(demux).append(" \\\n");
                sb.append("  --p-trim-left ").append(spTrimLeftF.getValue()).append(" \\\n");
                sb.append("  --p-trunc-len ").append(spTruncF.getValue()).append(" \\\n");
                sb.append("  --p-max-ee ").append(spMaxEEF.getValue()).append(" \\\n");
            }
            sb.append("  --p-trunc-q ").append(spTruncQ.getValue()).append(" \\\n");
            sb.append("  --p-chimera-method ").append(cbChimera.getSelectedItem()).append(" \\\n");
            String chimera = (String) cbChimera.getSelectedItem();
            if (!"none".equals(chimera)) {
                sb.append("  --p-min-fold-parent-over-abundance ").append(spMinFold.getValue()).append(" \\\n");
            }
            sb.append("  --p-n-threads ").append(spThreads.getValue()).append(" \\\n");
            sb.append("  --o-table ").append(outDir).append(File.separator).append("table.qza \\\n");
            sb.append("  --o-representative-sequences ").append(outDir).append(File.separator).append("rep-seqs.qza \\\n");
            sb.append("  --o-denoising-stats ").append(outDir).append(File.separator).append("denoising-stats.qza \\\n");
            sb.append("  --verbose");

        } else if (rbDeblur.isSelected()) {
            // --- Deblur preview ---
            sb.append("qiime deblur denoise-other \\\n");
            sb.append("  --i-demultiplexed-seqs ").append(demux).append(" \\\n");
            sb.append("  --p-trim-length ").append(spDeblurTrim.getValue()).append(" \\\n");
            sb.append("  --p-min-reads ").append(spDeblurMinReads.getValue()).append(" \\\n");
            sb.append("  --p-min-fold-parent-over-abundance ").append(spDeblurMinFold.getValue()).append(" \\\n");
            sb.append("  --p-jobs-to-start ").append(spDeblurJobs.getValue()).append(" \\\n");
            sb.append("  --o-table ").append(outDir).append(File.separator).append("table.qza \\\n");
            sb.append("  --o-representative-sequences ").append(outDir).append(File.separator).append("rep-seqs.qza \\\n");
            sb.append("  --o-stats ").append(outDir).append(File.separator).append("denoising-stats.qza \\\n");
            sb.append("  --verbose");

        } else {
            // --- VSEARCH preview (multi-step) ---
            sb.append("# Step 1: Merge paired reads (VSEARCH)\n");
            if (paired) {
                sb.append("qiime vsearch merge-pairs \\\n");
                sb.append("  --i-demultiplexed-seqs ").append(demux).append(" \\\n");
                sb.append("  --p-minovlen ").append(spVsMinOverlap.getValue()).append(" \\\n");
                if (cbVsStagger.isSelected()) sb.append("  --p-allowmergestagger \\\n");
                sb.append("  --p-threads ").append(spVsThreads.getValue()).append(" \\\n");
                sb.append("  --o-merged-sequences merged.qza \\\n");
                sb.append("  --o-unmerged-sequences unmerged.qza\n\n");
            } else {
                sb.append("# (Single-end mode: skipping merge, using forward reads directly)\n\n");
            }
            sb.append("# Step 2: Quality filter\n");
            sb.append("qiime quality-filter q-score \\\n");
            sb.append("  --i-demux ").append(paired ? "merged.qza" : demux).append(" \\\n");
            sb.append("  --p-min-quality ").append(spVsMinQual.getValue()).append(" \\\n");
            sb.append("  --p-min-length-fraction 0.75 \\\n");
            sb.append("  --o-filtered-sequences filtered.qza \\\n");
            sb.append("  --o-filter-stats filter-stats.qza\n\n");
            sb.append("# Step 3: Dereplicate\n");
            sb.append("qiime vsearch dereplicate-sequences \\\n");
            sb.append("  --i-sequences filtered.qza \\\n");
            sb.append("  --o-dereplicated-table derep-table.qza \\\n");
            sb.append("  --o-dereplicated-sequences derep-seqs.qza\n\n");
            sb.append("# Step 4: Cluster OTUs at ").append(spVsPercId.getValue()).append("\n");
            sb.append("qiime vsearch cluster-features-de-novo \\\n");
            sb.append("  --i-table derep-table.qza \\\n");
            sb.append("  --i-sequences derep-seqs.qza \\\n");
            sb.append("  --p-perc-identity ").append(spVsPercId.getValue()).append(" \\\n");
            sb.append("  --p-threads ").append(spVsThreads.getValue()).append(" \\\n");
            sb.append("  --o-clustered-table table.qza \\\n");
            sb.append("  --o-clustered-sequences rep-seqs.qza\n\n");
            if (!"none".equals(cbVsChimera.getSelectedItem())) {
                sb.append("# Step 5: Chimera removal (UCHIME de novo)\n");
                sb.append("qiime vsearch uchime-denovo \\\n");
                sb.append("  --i-table table.qza \\\n");
                sb.append("  --i-sequences rep-seqs.qza \\\n");
                sb.append("  --o-chimeras chimeras.qza \\\n");
                sb.append("  --o-nonchimeras nonchimeras.qza \\\n");
                sb.append("  --o-stats chimera-stats.qza\n\n");
                sb.append("# Step 6: Filter chimeras from table\n");
                sb.append("qiime feature-table filter-features \\\n");
                sb.append("  --i-table table.qza \\\n");
                sb.append("  --m-metadata-file nonchimeras.qza \\\n");
                sb.append("  --o-filtered-table table-nc.qza");
            }
        }

        cmdPreview.setText(sb.toString());
        cmdPreview.setCaretPosition(0);
    }

    private void toggleDenoiser() {
        boolean dada2 = rbDada2.isSelected();
        boolean deblur = rbDeblur.isSelected();
        boolean vsearch = rbVsearch.isSelected();
        dada2Panel.setVisible(dada2);
        deblurPanel.setVisible(deblur);
        vsearchPanel.setVisible(vsearch);

        // Show/hide single-end override (relevant for DADA2 and VSEARCH)
        cbForceSingle.setVisible(dada2 || vsearch);

        // Update tip banner
        if (dada2) {
            dada2Tip.setVisible(true);
        } else if (vsearch) {
            dada2Tip.setVisible(true);
        } else {
            dada2Tip.setVisible(false);
        }

        togglePairedFields();
        revalidate();
    }

    /** Show/hide reverse-read parameters based on paired/single mode. */
    private void togglePairedFields() {
        boolean showReverse = !isEffectivelySingle() && rbDada2.isSelected();
        lblTrimLeftR.setVisible(showReverse);
        spTrimLeftR.setVisible(showReverse);
        lblTruncR.setVisible(showReverse);
        spTruncR.setVisible(showReverse);
        lblMaxEER.setVisible(showReverse);
        spMaxEER.setVisible(showReverse);
        revalidate();
    }

    private void refreshRunState() {
        runBtn.setEnabled(!demuxPicker.isEmpty());
    }

    private void executeDenoising() {
        runBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        statusLabel.setText("<html><span style='color:#64748B'>Processing\u2026 (this may take a while)</span></html>");
        console.clear();

        final String demuxFile = demuxPicker.getPath();
        final String outDir = wizard.get("output.dir",
                new File(demuxFile).getParent());
        final boolean useDada2 = rbDada2.isSelected();
        final boolean useVsearch = rbVsearch.isSelected();
        final boolean paired = !isEffectivelySingle();

        new Thread(() -> {
            try {
                new File(outDir).mkdirs();
                String tableQza   = outDir + File.separator + "table.qza";
                String repSeqsQza = outDir + File.separator + "rep-seqs.qza";
                String statsQza   = outDir + File.separator + "denoising-stats.qza";

                if (useDada2) {
                    executeDada2(demuxFile, outDir, paired, tableQza, repSeqsQza, statsQza);
                } else if (useVsearch) {
                    executeVsearch(demuxFile, outDir, paired, tableQza, repSeqsQza, statsQza);
                } else {
                    executeDeblur(demuxFile, outDir, tableQza, repSeqsQza, statsQza);
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

    // ========================================================================
    // DADA2 execution
    // ========================================================================
    private void executeDada2(String demuxFile, String outDir, boolean paired,
                              String tableQza, String repSeqsQza, String statsQza) throws Exception {
        int trimLeftF = (int) spTrimLeftF.getValue();
        int truncF    = (int) spTruncF.getValue();
        int trimLeftR = (int) spTrimLeftR.getValue();
        int truncR    = (int) spTruncR.getValue();
        String chimera = (String) cbChimera.getSelectedItem();
        int threads   = (int) spThreads.getValue();
        double maxEEF = (double) spMaxEEF.getValue();
        double maxEER = (double) spMaxEER.getValue();
        int truncQ    = (int) spTruncQ.getValue();
        double minFold = (double) spMinFold.getValue();

        QiimeCommand cmd;
        if (paired) {
            cmd = new QiimeCommand("qiime dada2 denoise-paired")
                    .arg("--i-demultiplexed-seqs", demuxFile)
                    .arg("--p-trim-left-f", trimLeftF)
                    .arg("--p-trim-left-r", trimLeftR)
                    .arg("--p-trunc-len-f", truncF)
                    .arg("--p-trunc-len-r", truncR)
                    .arg("--p-max-ee-f", maxEEF)
                    .arg("--p-max-ee-r", maxEER)
                    .arg("--p-trunc-q", truncQ)
                    .arg("--p-chimera-method", chimera);
            if (!"none".equals(chimera)) {
                cmd.arg("--p-min-fold-parent-over-abundance", minFold);
            }
            cmd.arg("--p-n-threads", threads)
                    .arg("--o-table", tableQza)
                    .arg("--o-representative-sequences", repSeqsQza)
                    .arg("--o-denoising-stats", statsQza)
                    .flag("--verbose")
                    .workDir(outDir);
        } else {
            cmd = new QiimeCommand("qiime dada2 denoise-single")
                    .arg("--i-demultiplexed-seqs", demuxFile)
                    .arg("--p-trim-left", trimLeftF)
                    .arg("--p-trunc-len", truncF)
                    .arg("--p-max-ee", maxEEF)
                    .arg("--p-trunc-q", truncQ)
                    .arg("--p-chimera-method", chimera);
            if (!"none".equals(chimera)) {
                cmd.arg("--p-min-fold-parent-over-abundance", minFold);
            }
            cmd.arg("--p-n-threads", threads)
                    .arg("--o-table", tableQza)
                    .arg("--o-representative-sequences", repSeqsQza)
                    .arg("--o-denoising-stats", statsQza)
                    .flag("--verbose")
                    .workDir(outDir);
        }

        runningCmd = cmd;
        int exit = cmd.run(console);

        if (exit == 0) {
            exportStats(outDir, statsQza);
            denoiseSuccess(outDir, tableQza, repSeqsQza, statsQza);
        } else {
            denoiseFail();
        }
    }

    // ========================================================================
    // Deblur execution
    // ========================================================================
    private void executeDeblur(String demuxFile, String outDir,
                               String tableQza, String repSeqsQza, String statsQza) throws Exception {
        int trimLen   = (int) spDeblurTrim.getValue();
        int jobs      = (int) spDeblurJobs.getValue();
        int minReads  = (int) spDeblurMinReads.getValue();
        double minFoldDeblur = (double) spDeblurMinFold.getValue();

        QiimeCommand cmd = new QiimeCommand("qiime deblur denoise-other")
                .arg("--i-demultiplexed-seqs", demuxFile)
                .arg("--p-trim-length", trimLen)
                .arg("--p-min-reads", minReads)
                .arg("--p-min-fold-parent-over-abundance", minFoldDeblur)
                .arg("--p-jobs-to-start", jobs)
                .arg("--o-table", tableQza)
                .arg("--o-representative-sequences", repSeqsQza)
                .arg("--o-stats", statsQza)
                .flag("--verbose")
                .workDir(outDir);

        runningCmd = cmd;
        int exit = cmd.run(console);

        if (exit == 0) {
            exportStats(outDir, statsQza);
            denoiseSuccess(outDir, tableQza, repSeqsQza, statsQza);
        } else {
            denoiseFail();
        }
    }

    // ========================================================================
    // VSEARCH OTU clustering execution (multi-step)
    // ========================================================================
    private void executeVsearch(String demuxFile, String outDir, boolean paired,
                                String tableQza, String repSeqsQza, String statsQza) throws Exception {
        double percId    = (double) spVsPercId.getValue();
        int minOverlap   = (int) spVsMinOverlap.getValue();
        int minQual      = (int) spVsMinQual.getValue();
        int threads      = (int) spVsThreads.getValue();
        int minLen       = (int) spVsMinLen.getValue();
        boolean stagger  = cbVsStagger.isSelected();
        boolean chimera  = !"none".equals(cbVsChimera.getSelectedItem());

        String inputForFilter = demuxFile;

        // ---- Step 1: Merge paired reads (if paired) ----
        if (paired) {
            SwingUtilities.invokeLater(() -> {
                console.info("=== Step 1/6: Merging paired-end reads (VSEARCH) ===");
                statusLabel.setText("<html><span style='color:#64748B'>Step 1: Merging reads\u2026</span></html>");
            });

            String mergedQza = outDir + File.separator + "merged.qza";
            String unmergedQza = outDir + File.separator + "unmerged.qza";

            QiimeCommand mergeCmd = new QiimeCommand("qiime vsearch merge-pairs")
                    .arg("--i-demultiplexed-seqs", demuxFile)
                    .arg("--p-minovlen", minOverlap)
                    .arg("--p-threads", threads)
                    .arg("--o-merged-sequences", mergedQza)
                    .arg("--o-unmerged-sequences", unmergedQza);
            if (stagger) mergeCmd.flag("--p-allowmergestagger");
            mergeCmd.flag("--verbose").workDir(outDir);

            runningCmd = mergeCmd;
            int exit = mergeCmd.run(console);
            if (exit != 0) { denoiseFail(); return; }
            inputForFilter = mergedQza;
            SwingUtilities.invokeLater(() -> console.ok("Merge complete."));
        } else {
            SwingUtilities.invokeLater(() ->
                    console.info("=== Step 1: Skipped (single-end mode) ==="));
        }

        // ---- Step 2: Quality filter ----
        SwingUtilities.invokeLater(() -> {
            console.info("=== Step 2/6: Quality filtering ===");
            statusLabel.setText("<html><span style='color:#64748B'>Step 2: Quality filtering\u2026</span></html>");
        });

        String filteredQza = outDir + File.separator + "filtered.qza";
        String filterStatsQza = outDir + File.separator + "filter-stats.qza";

        QiimeCommand filterCmd = new QiimeCommand("qiime quality-filter q-score")
                .arg("--i-demux", inputForFilter)
                .arg("--p-min-quality", minQual)
                .arg("--p-min-length-fraction", 0.75)
                .arg("--o-filtered-sequences", filteredQza)
                .arg("--o-filter-stats", filterStatsQza)
                .flag("--verbose")
                .workDir(outDir);

        runningCmd = filterCmd;
        int filterExit = filterCmd.run(console);
        if (filterExit != 0) { denoiseFail(); return; }
        SwingUtilities.invokeLater(() -> console.ok("Quality filtering complete."));

        // ---- Step 3: Dereplicate ----
        SwingUtilities.invokeLater(() -> {
            console.info("=== Step 3/6: Dereplicating sequences ===");
            statusLabel.setText("<html><span style='color:#64748B'>Step 3: Dereplicating\u2026</span></html>");
        });

        String derepTableQza = outDir + File.separator + "derep-table.qza";
        String derepSeqsQza = outDir + File.separator + "derep-seqs.qza";

        QiimeCommand derepCmd = new QiimeCommand("qiime vsearch dereplicate-sequences")
                .arg("--i-sequences", filteredQza)
                .arg("--o-dereplicated-table", derepTableQza)
                .arg("--o-dereplicated-sequences", derepSeqsQza)
                .flag("--verbose")
                .workDir(outDir);

        runningCmd = derepCmd;
        int derepExit = derepCmd.run(console);
        if (derepExit != 0) { denoiseFail(); return; }
        SwingUtilities.invokeLater(() -> console.ok("Dereplication complete."));

        // ---- Step 4: Cluster OTUs ----
        SwingUtilities.invokeLater(() -> {
            console.info("=== Step 4/6: Clustering OTUs at " + percId + " identity ===");
            statusLabel.setText("<html><span style='color:#64748B'>Step 4: Clustering OTUs\u2026</span></html>");
        });

        QiimeCommand clusterCmd = new QiimeCommand("qiime vsearch cluster-features-de-novo")
                .arg("--i-table", derepTableQza)
                .arg("--i-sequences", derepSeqsQza)
                .arg("--p-perc-identity", percId)
                .arg("--p-threads", threads)
                .arg("--o-clustered-table", tableQza)
                .arg("--o-clustered-sequences", repSeqsQza)
                .flag("--verbose")
                .workDir(outDir);

        runningCmd = clusterCmd;
        int clusterExit = clusterCmd.run(console);
        if (clusterExit != 0) { denoiseFail(); return; }
        SwingUtilities.invokeLater(() -> console.ok("OTU clustering complete."));

        // ---- Step 5: Chimera removal (optional) ----
        String finalTableQza = tableQza;
        String finalRepSeqsQza = repSeqsQza;

        if (chimera) {
            SwingUtilities.invokeLater(() -> {
                console.info("=== Step 5/6: Chimera removal (UCHIME de novo) ===");
                statusLabel.setText("<html><span style='color:#64748B'>Step 5: Removing chimeras\u2026</span></html>");
            });

            String chimerasQza = outDir + File.separator + "chimeras.qza";
            String nonchimerasQza = outDir + File.separator + "nonchimeras.qza";
            String chimeraStatsQza = outDir + File.separator + "chimera-stats.qza";

            QiimeCommand uchimeCmd = new QiimeCommand("qiime vsearch uchime-denovo")
                    .arg("--i-table", tableQza)
                    .arg("--i-sequences", repSeqsQza)
                    .arg("--o-chimeras", chimerasQza)
                    .arg("--o-nonchimeras", nonchimerasQza)
                    .arg("--o-stats", chimeraStatsQza)
                    .flag("--verbose")
                    .workDir(outDir);

            runningCmd = uchimeCmd;
            int uchimeExit = uchimeCmd.run(console);
            if (uchimeExit != 0) { denoiseFail(); return; }

            // Filter chimeras from table
            SwingUtilities.invokeLater(() -> {
                console.info("=== Step 6/6: Filtering chimeric features ===");
                statusLabel.setText("<html><span style='color:#64748B'>Step 6: Filtering\u2026</span></html>");
            });

            String tableNcQza = outDir + File.separator + "table-nc.qza";
            String repSeqsNcQza = outDir + File.separator + "rep-seqs-nc.qza";

            QiimeCommand filterChimTable = new QiimeCommand("qiime feature-table filter-features")
                    .arg("--i-table", tableQza)
                    .arg("--m-metadata-file", nonchimerasQza)
                    .arg("--o-filtered-table", tableNcQza)
                    .flag("--verbose")
                    .workDir(outDir);
            runningCmd = filterChimTable;
            int ftExit = filterChimTable.run(console);
            if (ftExit != 0) { denoiseFail(); return; }

            // Filter chimeras from rep-seqs
            QiimeCommand filterChimSeqs = new QiimeCommand("qiime feature-table filter-seqs")
                    .arg("--i-data", repSeqsQza)
                    .arg("--m-metadata-file", nonchimerasQza)
                    .arg("--o-filtered-data", repSeqsNcQza)
                    .flag("--verbose")
                    .workDir(outDir);
            runningCmd = filterChimSeqs;
            filterChimSeqs.run(console);

            // Use chimera-free versions as final output
            finalTableQza = tableNcQza;
            finalRepSeqsQza = repSeqsNcQza;

            SwingUtilities.invokeLater(() -> console.ok("Chimera removal complete."));
        } else {
            SwingUtilities.invokeLater(() -> console.info("Steps 5-6: Chimera removal skipped."));
        }

        // Export filter stats as the "denoising stats"
        exportStats(outDir, filterStatsQza);

        denoiseSuccess(outDir, finalTableQza, finalRepSeqsQza, filterStatsQza);
    }

    // ========================================================================
    // Shared post-processing
    // ========================================================================
    private void exportStats(String outDir, String statsQza) throws Exception {
        SwingUtilities.invokeLater(() ->
                console.info("Exporting stats to TSV\u2026"));

        String statsTsv = outDir + File.separator + "denoising-stats.tsv";
        String exportDir = outDir + File.separator + "stats-export";

        // Tabulate
        QiimeCommand exportCmd = new QiimeCommand("qiime metadata tabulate")
                .arg("--m-input-file", statsQza)
                .arg("--o-visualization", outDir + File.separator + "denoising-stats.qzv")
                .workDir(outDir);
        exportCmd.run(console);

        // Export as TSV
        QiimeCommand exportTsv = new QiimeCommand("qiime tools export")
                .arg("--input-path", statsQza)
                .arg("--output-path", exportDir)
                .workDir(outDir);
        int exportExit = exportTsv.run(console);

        if (exportExit == 0) {
            File exported = new File(exportDir, "stats.tsv");
            if (exported.exists()) {
                exported.renameTo(new File(statsTsv));
            }
        }
    }

    private void denoiseSuccess(String outDir, String tableQza, String repSeqsQza, String statsQza) {
        wizard.put("table.qza", tableQza);
        wizard.put("rep-seqs.qza", repSeqsQza);
        wizard.put("denoising-stats.qza", statsQza);
        wizard.put("output.dir", outDir);

        SwingUtilities.invokeLater(() -> {
            statusLabel.setText("<html><span style='color:#16A34A'>\u2713 Complete</span></html>");
            console.ok("Feature table: " + tableQza);
            console.ok("Rep sequences: " + repSeqsQza);
            console.ok("Proceed to Taxonomy assignment.");
            stepComplete = true;
            notifyStepCompletion();
        });
    }

    private void denoiseFail() {
        SwingUtilities.invokeLater(() ->
                statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Failed</span></html>"));
    }

    // ========================================================================
    // UI helpers
    // ========================================================================
    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }

    private JLabel label(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_BODY);
        return l;
    }

    private JLabel guideLabel(String html) {
        JLabel l = new JLabel(html);
        l.setFont(Theme.FONT_BODY);
        l.setForeground(Theme.INK_2);
        return l;
    }

    private JLabel tipLabel(String text, String tooltip) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_BODY);
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

    // ========================================================================
    // Barcode / Linker Auto-Detection
    // ========================================================================

    /** Trigger barcode detection in a background thread. */
    private void triggerBarcodeDetection() {
        if (detectionRunning || demuxPicker.isEmpty()) return;
        final String qzaPath = demuxPicker.getPath();
        if (qzaPath == null || !new File(qzaPath).isFile()) return;

        detectionRunning = true;
        lastDetection = null;

        // Show the card in "scanning" state
        SwingUtilities.invokeLater(() -> {
            detectionIcon.setText("\uD83D\uDD0D");
            detectionTitle.setText("Scanning reads for barcode/linker prefixes...");
            detectionBody.setText("<html>Analyzing FASTQ reads inside the .qza artifact. " +
                    "This checks for non-biological sequence at the start of your reads " +
                    "that could cause denoising failures.</html>");
            detectionBtnRow.setVisible(false);
            detectionCard.setVisible(true);
            revalidate();
            repaint();
        });

        new Thread(() -> {
            try {
                // Determine amplicon length for overlap estimation
                int ampLen = 460; // default V3-V4
                String amplicon = wizard.get("amplicon");
                if ("16S-V4".equals(amplicon))   ampLen = 253;
                else if ("ITS1".equals(amplicon)) ampLen = 300;
                else if ("ITS2".equals(amplicon)) ampLen = 350;
                BarcodeDetector.DetectionResult result = BarcodeDetector.analyze(qzaPath, ampLen);
                lastDetection = result;

                SwingUtilities.invokeLater(() -> {
                    if (result.detected) {
                        showDetectionFound(result);
                    } else {
                        showDetectionClean(result);
                    }
                    detectionRunning = false;
                });
            } catch (Exception e) {
                SwingUtilities.invokeLater(() -> {
                    detectionCard.setVisible(false);
                    detectionRunning = false;
                    revalidate();
                });
            }
        }, "BarcodeDetector").start();
    }

    /** Show the detection card when barcode/linker IS found (safety net). */
    private void showDetectionFound(BarcodeDetector.DetectionResult r) {
        detectionIcon.setText("\u26A0");  // warning sign
        detectionTitle.setText("Barcode / Linker Prefix Still Present in Reads");

        StringBuilder html = new StringBuilder("<html><body style='width:640px'>");
        html.append("<b>EzMAP v2 detected non-biological sequence at the start of your reads.</b> ")
            .append("This usually means the Cutadapt step was skipped or didn't fully remove ")
            .append("barcodes/linkers.<br><br>");

        html.append("<b>Forward reads:</b> ").append(escapeHtml(r.forwardDetail));
        if (r.avgReadLenF > 0) {
            html.append(" (avg length: ").append(r.avgReadLenF).append("bp)");
        }
        html.append("<br>");

        if (r.hasPairedEnd) {
            html.append("<b>Reverse reads:</b> ").append(escapeHtml(r.reverseDetail));
            if (r.avgReadLenR > 0) {
                html.append(" (avg length: ").append(r.avgReadLenR).append("bp)");
            }
            html.append("<br><br>");

            // Overlap warning — use amplicon length from wizard
            int effectiveF = r.avgReadLenF - r.suggestedTrimLeftF;
            int effectiveR = r.avgReadLenR - r.suggestedTrimLeftR;
            String ampRegion = wizard.get("amplicon");
            int ampLenDisp = 460;
            String regionLabel = "V3-V4";
            if ("16S-V4".equals(ampRegion))        { ampLenDisp = 253; regionLabel = "V4"; }
            else if ("16S-V3V4".equals(ampRegion)) { ampLenDisp = 460; regionLabel = "V3-V4"; }
            else if ("ITS1".equals(ampRegion))     { ampLenDisp = 300; regionLabel = "ITS1"; }
            else if ("ITS2".equals(ampRegion))     { ampLenDisp = 350; regionLabel = "ITS2"; }
            int overlap = effectiveF + effectiveR - ampLenDisp;
            if (overlap < 40) {
                html.append("<span style='color:#B91C1C'><b>\u26A0 Tight overlap warning:</b> ")
                    .append("After trimming, estimated overlap is only ~").append(Math.max(0, overlap))
                    .append("bp for ").append(regionLabel).append(" (~").append(ampLenDisp)
                    .append("bp). Truncation is set to 0 (no truncation) ")
                    .append("to preserve maximum overlap.</span><br><br>");
            }
        }

        html.append("<b>Recommended:</b> Go back to the <b>Cutadapt</b> step and run primer removal \u2014 ")
            .append("Cutadapt's <code>--p-front</code> will strip barcodes + primers automatically.<br><br>");

        html.append("<b>Quick fix (trim-left):</b> If you can't re-run Cutadapt, click <b>Apply Suggestions</b> ")
            .append("to set trim-left values that strip the non-biological prefixes before denoising: ")
            .append("Trim-left fwd = ").append(r.suggestedTrimLeftF)
            .append(", Trim-left rev = ").append(r.suggestedTrimLeftR)
            .append(", Truncate fwd = ").append(r.suggestedTruncF == 0 ? "0 (no truncation)" : r.suggestedTruncF)
            .append(", Truncate rev = ").append(r.suggestedTruncR == 0 ? "0 (no truncation)" : r.suggestedTruncR);

        html.append("</body></html>");
        detectionBody.setText(html.toString());
        detectionBtnRow.setVisible(true);

        detectionCard.setVisible(true);
        revalidate();
        repaint();
    }

    /** Show the detection card when reads are clean (no barcode detected). */
    private void showDetectionClean(BarcodeDetector.DetectionResult r) {
        detectionIcon.setText("\u2705");  // green check
        detectionTitle.setText("Reads Look Clean — No Barcode/Linker Detected");

        StringBuilder html = new StringBuilder("<html><body style='width:640px'>");
        html.append("No non-biological barcode or linker prefix was detected at the start of your reads. ");
        html.append("Your reads appear ready for denoising with default trim-left = 0.");
        if (r.avgReadLenF > 0) {
            html.append("<br>Average read lengths: forward = ").append(r.avgReadLenF).append("bp");
            if (r.hasPairedEnd && r.avgReadLenR > 0) {
                html.append(", reverse = ").append(r.avgReadLenR).append("bp");
            }
            html.append(".");
        }
        html.append("</body></html>");

        detectionBody.setText(html.toString());
        detectionBtnRow.setVisible(false);

        detectionCard.setVisible(true);

        // Auto-hide clean result after 8 seconds
        Timer hideTimer = new Timer(8000, e -> {
            detectionCard.setVisible(false);
            revalidate();
        });
        hideTimer.setRepeats(false);
        hideTimer.start();

        revalidate();
        repaint();
    }

    /** Apply detection results to the trim/truncation spinners. */
    private void applyDetectionResults() {
        if (lastDetection == null) return;
        BarcodeDetector.DetectionResult r = lastDetection;

        spTrimLeftF.setValue(r.suggestedTrimLeftF);
        spTruncF.setValue(r.suggestedTruncF);

        if (r.hasPairedEnd) {
            spTrimLeftR.setValue(r.suggestedTrimLeftR);
            spTruncR.setValue(r.suggestedTruncR);
        }

        // Collapse the detection card to a small confirmation
        detectionIcon.setText("\u2705");
        detectionTitle.setText("Suggestions Applied");
        detectionBody.setText("<html>Trim-left and truncation values have been updated. " +
                "You can still adjust them manually before running.</html>");
        detectionBtnRow.setVisible(false);

        // Mark smart trim as applied so it doesn't overwrite
        smartTrimApplied = true;

        refreshCmdPreview();

        // Auto-hide after 5 seconds
        Timer hideTimer = new Timer(5000, e -> {
            detectionCard.setVisible(false);
            revalidate();
        });
        hideTimer.setRepeats(false);
        hideTimer.start();

        revalidate();
        repaint();
    }

    private static String escapeHtml(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
