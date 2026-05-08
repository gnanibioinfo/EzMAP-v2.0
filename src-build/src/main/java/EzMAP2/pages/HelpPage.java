package EzMAP2.pages;

import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.*;
import java.awt.*;

/**
 * Help & Technical Reference dialog — opens from the top-bar Help button.
 *
 * Addresses reviewer concerns:
 *   1. What "optimized" means for Easy Mode defaults and the evidence base
 *   2. Complete list of default parameters for Easy Mode
 *   3. Easy Mode vs Expert Mode comparison table
 *   4. Software and database versions
 *   5. Default similarity / confidence thresholds
 *   6. Pipeline architecture overview
 */
public class HelpPage extends JDialog {

    public HelpPage(Frame owner) {
        super(owner, "EzMAP v2 \u2014 Technical Reference & Help", true);
        setSize(820, 700);
        setMinimumSize(new Dimension(700, 500));
        setLocationRelativeTo(owner);

        JPanel root = new JPanel(new BorderLayout());
        root.setBackground(Theme.BACKGROUND);

        // ---- Header ----
        JPanel header = new JPanel(new BorderLayout());
        header.setBackground(Theme.SIDEBAR_TOP);
        header.setBorder(new EmptyBorder(14, 20, 14, 20));
        JLabel title = new JLabel("\uD83D\uDCD6  EzMAP v2 Technical Reference");
        title.setFont(Theme.FONT_PAGE_TITLE.deriveFont(18f));
        title.setForeground(Color.WHITE);
        header.add(title, BorderLayout.WEST);
        JLabel ver = new JLabel("v2.0");
        ver.setFont(Theme.FONT_SMALL);
        ver.setForeground(new Color(200, 200, 200));
        header.add(ver, BorderLayout.EAST);
        root.add(header, BorderLayout.NORTH);

        // ---- Tabbed body ----
        JTabbedPane tabs = new JTabbedPane(JTabbedPane.TOP);
        tabs.setFont(Theme.FONT_BODY);
        tabs.addTab("Default Parameters", buildDefaultParamsTab());
        tabs.addTab("Easy vs Expert Mode", buildComparisonTab());
        tabs.addTab("Plugin Versions", buildVersionsTab());
        tabs.addTab("Parameter Rationale", buildRationaleTab());
        root.add(tabs, BorderLayout.CENTER);

        // ---- Footer ----
        JPanel footer = new JPanel(new FlowLayout(FlowLayout.RIGHT, 10, 0));
        footer.setBackground(Theme.SURFACE);
        footer.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createMatteBorder(1, 0, 0, 0, Theme.BORDER),
                new EmptyBorder(10, 18, 10, 18)));
        PrimaryButton closeBtn = new PrimaryButton("Close");
        closeBtn.addActionListener(e -> dispose());
        footer.add(closeBtn);
        root.add(footer, BorderLayout.SOUTH);

        setContentPane(root);
    }

    // ========================================================================
    // Tab 1: Default Parameters (Easy Mode)
    // ========================================================================
    private JScrollPane buildDefaultParamsTab() {
        JPanel panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setOpaque(false);
        panel.setBorder(new EmptyBorder(14, 18, 14, 18));

        // Cutadapt defaults
        panel.add(sectionTitle("Primer Removal (Cutadapt)"));
        panel.add(paramTable(new String[][]{
            {"--p-front-f / --p-front-r", "Per-amplicon", "Auto-set from amplicon region (e.g. CCTACGGGNGGCWGCAG / GACTACHVGGGTATCTAATCC for 16S-V3V4)"},
            {"--p-error-rate",            "0.1 (10%)",    "Maximum mismatch rate for primer matching"},
            {"--p-times",                 "1",            "Number of primer removal rounds"},
            {"--p-overlap",               "3",            "Minimum bases of primer that must overlap read"},
            {"--p-minimum-length",        "50",           "Discard reads shorter than this after trimming"},
            {"--p-discard-untrimmed",     "true",         "Remove reads where no primer was found"},
            {"--p-cores",                 "= --threads",  "Parallel CPU cores for Cutadapt"},
        }));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("Quality-Driven Trimming (Smart Trim)"));
        panel.add(paramTable(new String[][]{
            {"Forward Q floor",     "25",   "Truncate forward reads where median quality drops below Q25"},
            {"Reverse Q floor",     "20",   "Truncate reverse reads where median quality drops below Q20"},
            {"Minimum length",      "150",  "Minimum read length after truncation to retain"},
            {"Method",              "Sliding window",  "Scans quality plot from 3' end to find optimal truncation point"},
        }));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("Denoising (DADA2) \u2014 Default Denoiser"));
        panel.add(Box.createVerticalStrut(2));
        panel.add(noteLabel("Trim/truncate values are determined by Smart Trim (quality-driven), not hard-coded."));
        panel.add(paramTable(new String[][]{
            {"--p-trim-left-f / -r",   "0",           "Bases removed from read start (0 because Cutadapt already removed primers)"},
            {"--p-trunc-len-f / -r",   "Smart Trim",  "Set by quality analysis; e.g. 260/220 for 16S-V3V4"},
            {"--p-max-ee",             "2.0",          "Max expected errors \u2014 reads exceeding this are discarded"},
            {"--p-trunc-q",            "2",            "Truncate at first base with Q <= this (2 = effectively off)"},
            {"--p-chimera-method",     "consensus",    "Per-sample chimera detection, then cross-sample voting"},
            {"--p-min-fold-parent-over-abundance", "1.0", "Min abundance ratio of parent sequences to chimera"},
            {"--p-n-threads",          "= --threads",  "CPU threads for DADA2 error model learning"},
        }));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("Taxonomy Classification"));
        panel.add(paramTable(new String[][]{
            {"Method",                 "classify-sklearn",  "Naive Bayes classifier (scikit-learn)"},
            {"--p-confidence",         "0.7",               "Minimum posterior probability for taxonomy assignment"},
            {"--p-n-jobs",             "= --threads",       "Parallel classification threads"},
            {"--p-reads-per-batch",    "auto",              "Automatic batching based on available memory"},
        }));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("Phylogenetic Tree"));
        panel.add(paramTable(new String[][]{
            {"Alignment",    "MAFFT",        "Multiple sequence alignment with MAFFT"},
            {"Tree method",  "FastTree",     "Approximately maximum-likelihood phylogeny"},
            {"Rooting",      "Midpoint",     "Rooted at midpoint of longest branch"},
        }));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("Global Settings"));
        panel.add(paramTable(new String[][]{
            {"--threads",     "4",       "Default CPU threads for all parallelizable steps"},
            {"--denoiser",    "dada2",   "DADA2 used by default; Deblur available as alternative"},
            {"--low-memory",  "false",   "When enabled, forces single-threaded DADA2 for low-RAM systems"},
        }));

        JScrollPane scroll = new JScrollPane(panel);
        scroll.setBorder(BorderFactory.createEmptyBorder());
        scroll.getVerticalScrollBar().setUnitIncrement(14);
        return scroll;
    }

    // ========================================================================
    // Tab 2: Easy Mode vs Expert Mode Comparison
    // ========================================================================
    private JScrollPane buildComparisonTab() {
        JPanel panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setOpaque(false);
        panel.setBorder(new EmptyBorder(14, 18, 14, 18));

        panel.add(sectionTitle("Easy Mode vs Expert Mode \u2014 Parameter Comparison"));
        panel.add(Box.createVerticalStrut(6));
        panel.add(wrapLabel(
                "Easy Mode uses quality-driven defaults optimized for typical amplicon datasets. "
                + "Expert Mode exposes all underlying QIIME2 parameters for full user control."));
        panel.add(Box.createVerticalStrut(10));

        String[] cols = {"Parameter", "Easy Mode", "Expert Mode", "Impact on Results"};
        String[][] rows = {
            {"Primer sequences",         "Auto-set by amplicon",     "User-editable",                "Incorrect primers \u2192 most reads discarded"},
            {"Primer error rate",         "0.1 (fixed)",             "Adjustable (0.0\u20131.0)",     "Higher = more permissive matching, risk of false positives"},
            {"Primer removal rounds",     "1 (fixed)",               "Adjustable (1\u201310)",        "2+ rounds needed only for concatemer artifacts"},
            {"Primer overlap",            "3 (fixed)",               "Adjustable (1\u201350)",        "Higher = fewer false primer matches"},
            {"Discard untrimmed",         "Always on",               "Toggle on/off",                "Off \u2192 non-amplicon reads may enter pipeline"},
            {"Cutadapt cores",            "= global threads",        "Independent setting",          "Performance only (no effect on results)"},
            {"Trim/truncate values",      "Quality-driven (Smart Trim)", "User-specified",           "Critical \u2014 too aggressive = lost data, too lenient = errors"},
            {"Max expected errors",       "2.0 (fixed)",             "Adjustable (0.0\u2013100.0)",  "Lower = stricter quality filter, fewer ASVs retained"},
            {"Truncation quality",        "2 (effectively off)",     "Adjustable (0\u201340)",       "Higher values = aggressive per-read quality trimming"},
            {"Chimera method",            "consensus (fixed)",       "consensus / pooled / none",    "pooled = more sensitive; none = no chimera removal"},
            {"Min fold parent abundance", "1.0 (fixed)",             "Adjustable (0.1\u2013100)",    "Higher = more conservative chimera calling"},
            {"DADA2 threads",             "= global threads",        "Independent setting",          "Performance only"},
            {"Denoiser choice",           "DADA2 (default)",         "DADA2 or Deblur",              "Different algorithms; DADA2 resolves single-nucleotide variants"},
            {"Classification confidence", "0.7 (fixed)",             "Adjustable (0.0\u20131.0)",    "Lower = more assignments but less reliable"},
            {"Classification jobs",       "= global threads",        "Adjustable (1\u201364)",       "Performance only"},
            {"Reads per batch",           "auto",                    "Adjustable (0\u2013100k)",     "Controls memory usage for large datasets"},
            {"Classifier source",         "Pre-trained only",        "Pre-trained / Train new / Custom", "Region-specific training improves accuracy"},
            {"Reference database",        "User-selected at setup",  "User-selected + trainable",    "Database choice determines taxonomic resolution"},
        };

        JTable table = createStyledTable(cols, rows);
        JScrollPane tableScroll = new JScrollPane(table);
        tableScroll.setPreferredSize(new Dimension(0, 380));
        tableScroll.setBorder(BorderFactory.createLineBorder(Theme.BORDER));
        panel.add(tableScroll);

        panel.add(Box.createVerticalStrut(12));
        panel.add(noteLabel(
                "Parameters marked as 'fixed' in Easy Mode use values established by QIIME2 documentation and community best practices. "
                + "Expert Mode allows adjustment of all parameters shown above."));

        JScrollPane scroll = new JScrollPane(panel);
        scroll.setBorder(BorderFactory.createEmptyBorder());
        scroll.getVerticalScrollBar().setUnitIncrement(14);
        return scroll;
    }

    // ========================================================================
    // Tab 3: Software & Database Versions
    // ========================================================================
    private JScrollPane buildVersionsTab() {
        JPanel panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setOpaque(false);
        panel.setBorder(new EmptyBorder(14, 18, 14, 18));

        panel.add(sectionTitle("Core Software"));
        panel.add(paramTable(new String[][]{
            {"EzMAP v2",               "2.0",        "Java Swing GUI + R Shiny downstream"},
            {"QIIME2",               "2024.10+",   "Installed via conda (EzMAP v2-qiime2 environment)"},
            {"DADA2 (QIIME2 plugin)","1.28+",      "Amplicon sequence variant inference"},
            {"Deblur (QIIME2 plugin)","1.1+",      "Sub-OTU resolution via error profiles"},
            {"Cutadapt (QIIME2)",    "4.9+",       "Primer and adapter removal"},
            {"MAFFT",                "7.520+",     "Multiple sequence alignment"},
            {"FastTree",             "2.1.11+",    "Approximate maximum-likelihood trees"},
            {"scikit-learn",         "0.24+",      "Naive Bayes taxonomy classifier"},
            {"R",                    "4.2+",       "Downstream statistical analysis"},
            {"R Shiny",              "1.7+",       "Interactive downstream dashboard"},
            {"Java",                 "11+",        "Cross-platform GUI runtime"},
        }));

        panel.add(Box.createVerticalStrut(16));
        panel.add(sectionTitle("Reference Taxonomy Databases"));
        panel.add(paramTable(new String[][]{
            {"SILVA",         "138.2",    "16S/18S/23S rRNA; recommended for bacteria/archaea. SSURef NR99 full-length sequences."},
            {"Greengenes2",   "2024.09",  "16S rRNA; updated phylogenetic backbone with WoL2 tree. Successor to Greengenes 13_8."},
            {"UNITE",         "10.0",     "ITS (fungal); curated species hypothesis (SH) database. Dynamic clustering at 97\u201399% similarity."},
        }));

        panel.add(Box.createVerticalStrut(16));
        panel.add(sectionTitle("Key R Packages (Downstream Analysis)"));
        panel.add(paramTable(new String[][]{
            {"phyloseq",       "1.44+",   "Microbiome data manipulation and visualization"},
            {"vegan",          "2.6+",    "Community ecology (diversity, ordination)"},
            {"DESeq2",         "1.40+",   "Differential abundance testing"},
            {"ggplot2",        "3.4+",    "Publication-quality plotting"},
            {"microbiome",     "1.22+",   "Extended microbiome analysis utilities"},
        }));

        panel.add(Box.createVerticalStrut(16));
        panel.add(noteLabel(
                "Exact versions depend on the QIIME2 release installed. EzMAP v2 detects the installed QIIME2 version "
                + "at runtime \u2014 check Settings for your current version. Classifier .qza files are tied to the "
                + "scikit-learn version in your environment; re-train classifiers after major QIIME2 upgrades."));

        JScrollPane scroll = new JScrollPane(panel);
        scroll.setBorder(BorderFactory.createEmptyBorder());
        scroll.getVerticalScrollBar().setUnitIncrement(14);
        return scroll;
    }

    // ========================================================================
    // Tab 4: Parameter Rationale ("Optimized" explanation)
    // ========================================================================
    private JScrollPane buildRationaleTab() {
        JPanel panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setOpaque(false);
        panel.setBorder(new EmptyBorder(14, 18, 14, 18));

        panel.add(sectionTitle("What \"Optimized Defaults\" Means"));
        panel.add(Box.createVerticalStrut(4));
        panel.add(wrapLabel(
                "The Easy Mode defaults in EzMAP v2 are optimized for stability and reproducibility across typical "
                + "amplicon datasets, following established community best practices. They are not tuned for a single "
                + "benchmark but represent consensus recommendations from the QIIME2 documentation, published "
                + "tutorials, and peer-reviewed microbiome methodology literature."));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("Evidence Base for Default Values"));

        panel.add(Box.createVerticalStrut(6));
        panel.add(rationale("Confidence threshold = 0.7",
                "Bokulich et al. (2018) \"Optimizing taxonomic classification of marker-gene amplicon sequences\" "
                + "(Microbiome 6:90) systematically evaluated confidence thresholds and found 0.7 provides a balanced "
                + "trade-off between classification precision and recall. This is the QIIME2 default."));

        panel.add(rationale("Chimera method = consensus",
                "DADA2's consensus method (Callahan et al., 2016, Nature Methods 13:581) identifies chimeras independently "
                + "per sample, then applies cross-sample voting. This is recommended by the DADA2 developers for most datasets "
                + "and is robust against false positives in diverse communities."));

        panel.add(rationale("Max expected errors = 2.0",
                "The DADA2 default of 2.0 is recommended by Callahan et al. (2016). This filters reads with >2 expected "
                + "errors based on quality scores, retaining the vast majority of good reads while removing obvious noise."));

        panel.add(rationale("Smart Trim (quality-driven truncation)",
                "Rather than using fixed truncation lengths, EzMAP v2 analyzes per-base quality distributions from "
                + "the actual dataset to choose truncation points. This approach is recommended in the QIIME2 Moving Pictures "
                + "tutorial and Atacama Soil tutorial. The Q25/Q20 thresholds for forward/reverse reads account for "
                + "the well-documented pattern of faster quality decay in reverse Illumina reads (Schirmer et al., 2015, "
                + "Nucleic Acids Research 43:e37)."));

        panel.add(rationale("DADA2 as default denoiser",
                "DADA2 is recommended over OTU clustering for modern amplicon analysis (Callahan et al., 2017, "
                + "Nature Methods 14:135). It provides single-nucleotide resolution (ASVs), is reproducible without "
                + "reference databases, and has become the standard in the field."));

        panel.add(rationale("Primer removal before denoising",
                "Cutadapt-based primer removal before denoising is recommended by the QIIME2 documentation to prevent "
                + "primer heterogeneity from inflating ASV counts. The --p-discard-untrimmed flag ensures only true "
                + "amplicon reads enter the pipeline."));

        panel.add(rationale("Naive Bayes classifier (classify-sklearn)",
                "Bokulich et al. (2018) demonstrated that region-specific trained Naive Bayes classifiers outperform "
                + "BLAST-based and VSEARCH-based methods for taxonomy assignment. EzMAP v2 trains classifiers against the "
                + "specific primer region used in each study."));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("Parameters That Affect Analysis Results"));
        panel.add(Box.createVerticalStrut(4));
        panel.add(wrapLabel(
                "The following Easy Mode parameters have direct impact on biological conclusions and should "
                + "be noted by users. These are the parameters most likely to require adjustment for non-standard datasets:"));
        panel.add(Box.createVerticalStrut(6));

        panel.add(impactParam("Truncation lengths (Smart Trim)",
                "Determined per-dataset by quality analysis. Affects read merging success, ASV count, and taxonomic resolution. "
                + "For paired-end: forward + reverse truncate must exceed amplicon length by >= 20bp."));

        panel.add(impactParam("Classification confidence (0.7)",
                "Controls the precision-recall trade-off for taxonomy labels. Lowering to 0.5 increases assignments but risks "
                + "misclassification; raising to 0.9 reduces assignments to only high-confidence calls."));

        panel.add(impactParam("Chimera method (consensus)",
                "Choice between consensus, pooled, or none directly affects the number of retained ASVs. Pooled mode is more "
                + "aggressive and may be preferred for low-biomass samples."));

        panel.add(impactParam("Reference database (SILVA/GG2/UNITE)",
                "Database choice determines available taxonomy and naming conventions. SILVA 138.2 is most comprehensive for "
                + "bacteria/archaea; UNITE is required for ITS/fungal studies."));

        panel.add(impactParam("Primer sequences",
                "Incorrect primers will cause nearly all reads to be discarded by Cutadapt. Verify that the selected "
                + "amplicon region matches your wet-lab protocol."));

        panel.add(Box.createVerticalStrut(12));
        panel.add(sectionTitle("References"));
        panel.add(refLabel("Callahan BJ et al. (2016) DADA2: High-resolution sample inference from Illumina amplicon data. Nature Methods 13:581-583."));
        panel.add(refLabel("Callahan BJ et al. (2017) Exact sequence variants should replace operational taxonomic units in marker-gene data analysis. ISME J 11:2639-2643."));
        panel.add(refLabel("Bokulich NA et al. (2018) Optimizing taxonomic classification of marker-gene amplicon sequences with QIIME 2's q2-feature-classifier plugin. Microbiome 6:90."));
        panel.add(refLabel("Schirmer M et al. (2015) Insight into biases and sequencing errors for amplicon sequencing with the Illumina MiSeq platform. Nucleic Acids Res 43:e37."));
        panel.add(refLabel("Bolyen E et al. (2019) Reproducible, interactive, scalable and extensible microbiome data science using QIIME 2. Nature Biotechnology 37:852-857."));
        panel.add(refLabel("Quast C et al. (2013) The SILVA ribosomal RNA gene database project. Nucleic Acids Res 41:D590-D596."));

        JScrollPane scroll = new JScrollPane(panel);
        scroll.setBorder(BorderFactory.createEmptyBorder());
        scroll.getVerticalScrollBar().setUnitIncrement(14);
        return scroll;
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    /** Creates a 3-column parameter table: Parameter | Default | Description */
    private JComponent paramTable(String[][] data) {
        String[] cols = {"Parameter", "Default", "Description"};
        JTable table = createStyledTable(cols, data);
        table.getColumnModel().getColumn(0).setPreferredWidth(200);
        table.getColumnModel().getColumn(1).setPreferredWidth(100);
        table.getColumnModel().getColumn(2).setPreferredWidth(440);
        int rowHeight = 24;
        table.setRowHeight(rowHeight);

        // Auto-resize row height for long descriptions
        for (int row = 0; row < table.getRowCount(); row++) {
            int maxH = rowHeight;
            for (int col = 0; col < table.getColumnCount(); col++) {
                TableCellRenderer renderer = table.getCellRenderer(row, col);
                Component comp = table.prepareRenderer(renderer, row, col);
                // Set width explicitly so JTextArea wraps correctly before layout
                int w = table.getColumnModel().getColumn(col).getPreferredWidth();
                comp.setSize(new Dimension(w, Short.MAX_VALUE));
                maxH = Math.max(maxH, comp.getPreferredSize().height + 2);
            }
            table.setRowHeight(row, maxH);
        }

        JScrollPane sp = new JScrollPane(table);
        int totalH = table.getTableHeader().getPreferredSize().height + 4;
        for (int r = 0; r < table.getRowCount(); r++) totalH += table.getRowHeight(r);
        totalH = Math.min(totalH, 400);
        sp.setPreferredSize(new Dimension(0, totalH));
        sp.setMaximumSize(new Dimension(Integer.MAX_VALUE, totalH));
        sp.setBorder(BorderFactory.createLineBorder(Theme.BORDER));
        sp.setAlignmentX(LEFT_ALIGNMENT);
        return sp;
    }

    private static JTable createStyledTable(String[] columns, String[][] data) {
        DefaultTableModel model = new DefaultTableModel(data, columns) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        JTable table = new JTable(model);
        table.setFont(Theme.FONT_SMALL);
        table.setRowHeight(22);
        table.setShowGrid(true);
        table.setGridColor(new Color(0xE2, 0xE8, 0xF0));
        table.setSelectionBackground(new Color(0xDB, 0xEA, 0xFE));
        table.getTableHeader().setFont(Theme.FONT_BODY_BOLD);
        table.getTableHeader().setBackground(new Color(0xF1, 0xF5, 0xF9));
        table.getTableHeader().setForeground(Theme.INK_1);

        // Word-wrap renderer for description columns
        DefaultTableCellRenderer wrapRenderer = new DefaultTableCellRenderer() {
            @Override
            public Component getTableCellRendererComponent(JTable t, Object val,
                    boolean sel, boolean foc, int row, int col) {
                JTextArea area = new JTextArea(val != null ? val.toString() : "");
                area.setLineWrap(true);
                area.setWrapStyleWord(true);
                area.setFont(Theme.FONT_SMALL);
                area.setBorder(BorderFactory.createEmptyBorder(1, 4, 1, 4));
                if (sel) {
                    area.setBackground(t.getSelectionBackground());
                    area.setForeground(t.getSelectionForeground());
                } else {
                    area.setBackground(row % 2 == 0 ? Color.WHITE : new Color(0xF8, 0xFA, 0xFC));
                    area.setForeground(Theme.INK_1);
                }
                // Calculate preferred height — use preferredWidth as fallback before layout
                int colW = t.getColumnModel().getColumn(col).getWidth();
                if (colW <= 0) colW = t.getColumnModel().getColumn(col).getPreferredWidth();
                area.setSize(colW, Short.MAX_VALUE);
                return area;
            }
        };

        // Apply wrap renderer to last column (description)
        table.getColumnModel().getColumn(table.getColumnCount() - 1).setCellRenderer(wrapRenderer);

        // Bold first column
        DefaultTableCellRenderer boldRenderer = new DefaultTableCellRenderer();
        boldRenderer.setFont(Theme.FONT_BODY_BOLD);
        table.getColumnModel().getColumn(0).setCellRenderer(new DefaultTableCellRenderer() {
            @Override
            public Component getTableCellRendererComponent(JTable t, Object val,
                    boolean sel, boolean foc, int row, int col) {
                Component c = super.getTableCellRendererComponent(t, val, sel, foc, row, col);
                c.setFont(Theme.FONT_SMALL.deriveFont(Font.BOLD));
                if (!sel) {
                    c.setBackground(row % 2 == 0 ? Color.WHITE : new Color(0xF8, 0xFA, 0xFC));
                }
                return c;
            }
        });

        table.setAutoResizeMode(JTable.AUTO_RESIZE_LAST_COLUMN);
        return table;
    }

    private JLabel sectionTitle(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_PAGE_TITLE.deriveFont(15f));
        l.setForeground(Theme.PRIMARY_DARK);
        l.setBorder(new EmptyBorder(6, 0, 4, 0));
        l.setAlignmentX(LEFT_ALIGNMENT);
        return l;
    }

    private JComponent wrapLabel(String text) {
        JTextArea area = new JTextArea(text);
        area.setLineWrap(true);
        area.setWrapStyleWord(true);
        area.setEditable(false);
        area.setOpaque(false);
        area.setFont(Theme.FONT_BODY);
        area.setForeground(Theme.INK_2);
        area.setBorder(new EmptyBorder(0, 0, 0, 0));
        area.setAlignmentX(LEFT_ALIGNMENT);
        area.setMaximumSize(new Dimension(Integer.MAX_VALUE, Integer.MAX_VALUE));
        return area;
    }

    private JComponent rationale(String param, String explanation) {
        JPanel p = new JPanel();
        p.setLayout(new BoxLayout(p, BoxLayout.Y_AXIS));
        p.setOpaque(false);
        p.setBorder(new EmptyBorder(4, 12, 8, 0));
        p.setAlignmentX(LEFT_ALIGNMENT);

        JLabel header = new JLabel("\u2022 " + param);
        header.setFont(Theme.FONT_BODY_BOLD);
        header.setForeground(Theme.INK_1);
        header.setAlignmentX(LEFT_ALIGNMENT);
        p.add(header);

        JTextArea body = new JTextArea(explanation);
        body.setLineWrap(true);
        body.setWrapStyleWord(true);
        body.setEditable(false);
        body.setOpaque(false);
        body.setFont(Theme.FONT_SMALL);
        body.setForeground(Theme.INK_3);
        body.setBorder(new EmptyBorder(2, 16, 0, 0));
        body.setAlignmentX(LEFT_ALIGNMENT);
        body.setMaximumSize(new Dimension(Integer.MAX_VALUE, Integer.MAX_VALUE));
        p.add(body);

        return p;
    }

    private JComponent impactParam(String param, String impact) {
        JPanel p = new JPanel();
        p.setLayout(new BoxLayout(p, BoxLayout.Y_AXIS));
        p.setOpaque(false);
        p.setBorder(new EmptyBorder(2, 12, 6, 0));
        p.setAlignmentX(LEFT_ALIGNMENT);

        JLabel header = new JLabel("\u26A0 " + param);
        header.setFont(Theme.FONT_BODY_BOLD);
        header.setForeground(new Color(0xCA, 0x8A, 0x04)); // warning amber
        header.setAlignmentX(LEFT_ALIGNMENT);
        p.add(header);

        JTextArea body = new JTextArea(impact);
        body.setLineWrap(true);
        body.setWrapStyleWord(true);
        body.setEditable(false);
        body.setOpaque(false);
        body.setFont(Theme.FONT_SMALL);
        body.setForeground(Theme.INK_2);
        body.setBorder(new EmptyBorder(2, 16, 0, 0));
        body.setAlignmentX(LEFT_ALIGNMENT);
        body.setMaximumSize(new Dimension(Integer.MAX_VALUE, Integer.MAX_VALUE));
        p.add(body);

        return p;
    }

    private JLabel noteLabel(String text) {
        JLabel l = new JLabel("<html><body style='width:650px'><i>" + text + "</i></body></html>");
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        l.setBorder(new EmptyBorder(4, 4, 4, 0));
        l.setAlignmentX(LEFT_ALIGNMENT);
        return l;
    }

    private JLabel refLabel(String citation) {
        JLabel l = new JLabel("<html><body style='width:650px'>\u2022 " + citation + "</body></html>");
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        l.setBorder(new EmptyBorder(2, 12, 2, 0));
        l.setAlignmentX(LEFT_ALIGNMENT);
        return l;
    }
}
