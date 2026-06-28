package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import java.awt.*;
import java.io.File;

/**
 * Expert Mode — Step 2: Import FASTQ files into a QIIME2 artifact (.qza).
 *
 * All settings (format, type, paired/single) are auto-detected from the
 * Validate Inputs step. User just confirms and clicks Run.
 */
public class ImportFilesPage extends BasePage {

    private final WizardController wizard;
    private boolean stepComplete = false;

    @Override public boolean isStepComplete() { return stepComplete; }

    // Input pickers
    private final DirectoryPicker manifestPicker;
    private final DirectoryPicker outputPicker;

    // Detected format display (read-only info)
    private final JLabel formatLabel  = new JLabel(" ");
    private final JLabel typeLabel    = new JLabel(" ");
    private final JLabel readLabel    = new JLabel(" ");

    // Controls
    private final PrimaryButton runBtn = new PrimaryButton("Run Import  \u2192");
    private final OutlineButton stopBtn = new OutlineButton("Stop");
    private final JLabel statusLabel = new JLabel(" ");
    private final LogConsole console = new LogConsole();
    private final JTextArea cmdPreview = new JTextArea(3, 60);

    private volatile QiimeCommand runningCmd;

    public ImportFilesPage(WizardController wizard) {
        super("Expert Mode — Step 2: Import Sequences",
              "Imports your FASTQ files into a QIIME2 artifact (.qza) using the manifest " +
              "and format detected in the previous step.");
        this.wizard = wizard;

        // ---- Card 1: Detected format (read-only) ----
        Card detectedCard = new Card("1 \u00B7 Detected Format");
        detectedCard.row(new InfoBanner(InfoBanner.Kind.INFO, "Auto-detected",
                "These settings were detected from your FASTQ files in the Validate Inputs step. " +
                "No changes needed.")).gap(8);

        JPanel infoGrid = new JPanel(new GridLayout(3, 2, 10, 4));
        infoGrid.setOpaque(false);
        JLabel fmtLbl = label("Import format:");
        fmtLbl.setToolTipText("The QIIME2 import format (e.g. PairedEndFastqManifestPhred33V2). Auto-detected from your FASTQ files.");
        infoGrid.add(fmtLbl);  infoGrid.add(formatLabel);
        JLabel typLbl = label("QIIME2 type:");
        typLbl.setToolTipText("The QIIME2 semantic type (e.g. SampleData[PairedEndSequencesWithQuality]). Determines how QIIME2 interprets the data.");
        infoGrid.add(typLbl);    infoGrid.add(typeLabel);
        JLabel rdLbl = label("Read type:");
        rdLbl.setToolTipText("Whether your data is paired-end (forward + reverse reads) or single-end. Determines the pipeline commands used.");
        infoGrid.add(rdLbl);       infoGrid.add(readLabel);
        detectedCard.row(infoGrid);
        add(detectedCard);

        // ---- Card 2: Input files ----
        Card inputCard = new Card("2 \u00B7 Input Files");

        inputCard.row(caption("Manifest file (from Validate step):"));
        manifestPicker = new DirectoryPicker("samples_manifest.tsv",
                f -> refreshRunState(), true);
        inputCard.row(manifestPicker).gap(8);

        inputCard.row(caption("Output directory:"));
        outputPicker = new DirectoryPicker("Select output directory",
                f -> refreshRunState());
        inputCard.row(outputPicker);
        add(inputCard);

        // ---- Card 3: Run ----
        Card runCard = new Card("3 \u00B7 Execute Import");
        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        btnRow.setOpaque(false);
        btnRow.add(runBtn);
        btnRow.add(stopBtn);
        statusLabel.setFont(Theme.FONT_BODY);
        btnRow.add(statusLabel);
        runCard.row(btnRow).gap(8);

        console.setPreferredSize(new Dimension(0, 180));
        runCard.row(console);
        add(runCard);

        // ---- Card 4: Command Preview ----
        Card previewCard = new Card("4 \u00B7 QIIME2 Command Preview");
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
        runBtn.addActionListener(e -> executeImport());
        stopBtn.addActionListener(e -> {
            if (runningCmd != null) runningCmd.cancel();
        });

        // Style labels
        for (JLabel l : new JLabel[]{formatLabel, typeLabel, readLabel}) {
            l.setFont(Theme.FONT_BODY_BOLD);
            l.setForeground(Theme.PRIMARY_DARK);
        }
    }

    @Override
    public void onShown() {
        // Auto-fill manifest path
        String fastqDir = wizard.get("fastq.dir");
        if (fastqDir != null && manifestPicker.isEmpty()) {
            File manifest = new File(fastqDir, "samples_manifest.tsv");
            if (manifest.isFile()) {
                manifestPicker.setPath(manifest.getAbsolutePath());
            }
        }

        // Auto-fill output directory
        String outDir = wizard.get("output.dir");
        if (outDir != null && outputPicker.isEmpty()) {
            outputPicker.setPath(outDir);
        }

        // Show detected format info
        String format = wizard.get("fastq.format");
        String type   = wizard.get("fastq.type");
        String readType = wizard.get("read.type");

        formatLabel.setText(format != null ? format : "(not detected \u2014 run Validate first)");
        typeLabel.setText(type != null ? type : "(not detected)");
        readLabel.setText(readType != null
                ? ("paired".equals(readType) ? "Paired-end" : "Single-end")
                : "(not detected)");

        refreshRunState();
        refreshCmdPreview();
    }

    private void refreshRunState() {
        runBtn.setEnabled(!manifestPicker.isEmpty() && !outputPicker.isEmpty());
    }

    private void refreshCmdPreview() {
        String format = wizard.get("fastq.format");
        String type   = wizard.get("fastq.type");
        boolean paired = "paired".equals(wizard.get("read.type", "paired"));

        String seqType = (type != null && !type.isEmpty()) ? type
                : (paired ? "SampleData[PairedEndSequencesWithQuality]"
                          : "SampleData[SequencesWithQuality]");
        String inputFormat = (format != null && !format.isEmpty()) ? format
                : (paired ? "PairedEndFastqManifestPhred33V2"
                          : "SingleEndFastqManifestPhred33V2");

        String manifest = manifestPicker.isEmpty() ? "<manifest.tsv>" : manifestPicker.getPath();
        String out = (outputPicker.isEmpty() ? "." : outputPicker.getPath())
                + File.separator + (paired ? "demux-paired.qza" : "demux-single.qza");

        StringBuilder sb = new StringBuilder();
        sb.append("qiime tools import \\\n");
        sb.append("  --type \"").append(seqType).append("\" \\\n");
        sb.append("  --input-format ").append(inputFormat).append(" \\\n");
        sb.append("  --input-path ").append(manifest).append(" \\\n");
        sb.append("  --output-path ").append(out);
        cmdPreview.setText(sb.toString());
        cmdPreview.setCaretPosition(0);
    }

    private void executeImport() {
        runBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        statusLabel.setText("<html><span style='color:#64748B'>Importing\u2026</span></html>");
        console.clear();

        final String manifest = manifestPicker.getPath();
        final String outDir = outputPicker.getPath();

        // Get auto-detected format and type
        final String detectedFormat = wizard.get("fastq.format");
        final String detectedType   = wizard.get("fastq.type");
        final boolean paired = "paired".equals(wizard.get("read.type", "paired"));

        new Thread(() -> {
            try {
                new File(outDir).mkdirs();

                String outputFile = outDir + File.separator +
                        (paired ? "demux-paired.qza" : "demux-single.qza");

                // Use auto-detected format, fallback to default paired Phred33
                String seqType = (detectedType != null && !detectedType.isEmpty())
                        ? detectedType
                        : (paired ? "SampleData[PairedEndSequencesWithQuality]"
                                  : "SampleData[SequencesWithQuality]");

                String inputFormat = (detectedFormat != null && !detectedFormat.isEmpty())
                        ? detectedFormat
                        : (paired ? "PairedEndFastqManifestPhred33V2"
                                  : "SingleEndFastqManifestPhred33V2");

                SwingUtilities.invokeLater(() ->
                    console.info("Format: " + inputFormat + " | Type: " + seqType));

                QiimeCommand cmd = new QiimeCommand("qiime tools import")
                        .arg("--type", seqType)
                        .arg("--input-format", inputFormat)
                        .arg("--input-path", manifest)
                        .arg("--output-path", outputFile)
                        .workDir(outDir);

                runningCmd = cmd;
                int exit = cmd.run(console);

                if (exit == 0) {
                    wizard.put("demux.qza", outputFile);
                    wizard.put("output.dir", outDir);
                    wizard.put("read.type", paired ? "paired" : "single");

                    SwingUtilities.invokeLater(() -> {
                        statusLabel.setText("<html><span style='color:#16A34A'>\u2713 Import complete</span></html>");
                        console.ok("Output: " + outputFile);
                        console.ok("Proceed to Cutadapt (primer removal).");
                        stepComplete = true;
                        notifyStepCompletion();
                    });
                } else {
                    SwingUtilities.invokeLater(() ->
                            statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Import failed</span></html>"));
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

    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }

    private JLabel label(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_BODY);
        l.setForeground(Theme.INK_2);
        return l;
    }
}
