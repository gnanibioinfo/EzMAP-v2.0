package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.GhostButton;
import EzMAP2.ui.PrimaryButton;
import EzMAP2.ui.Theme;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;

/**
 * Landing page — first screen the user sees.
 * Two paths: "Full Analysis" (upstream + downstream) or "Downstream Only".
 */
public class WelcomePage extends BasePage {

    private final WizardController wizard;
    private String selectedPath = null;   // "full" or "downstream"
    private JPanel fullCard, downCard;
    private final PrimaryButton continueBtn = new PrimaryButton("Get Started  \u2192");

    // Preflight system check (memory + disk) shown on first display
    private final JLabel sysCheckLabel = new JLabel();
    private volatile boolean sysChecked = false;

    public WelcomePage(WizardController wizard) {
        super("Welcome to EzMAP v2.0",
              "Choose how you'd like to proceed. Run the full pipeline from raw FASTQ reads, " +
              "or jump straight to downstream analysis if you already have processed data.");
        this.wizard = wizard;

        // ---- Two-card row ----
        JPanel row = new JPanel(new GridLayout(1, 2, 20, 0));
        row.setOpaque(false);
        row.setAlignmentX(LEFT_ALIGNMENT);

        fullCard = buildCard(
                "Full Analysis",
                "\uD83D\uDD2C",   // microscope emoji
                "Run the complete QIIME2 pipeline from raw FASTQ reads to results — " +
                "includes environment setup, database configuration, quality control, " +
                "denoising, taxonomy, and phylogeny. Produces a ready-to-analyze bundle " +
                "for downstream visualization and statistics.",
                new String[]{
                        "Environment & database setup wizard",
                        "Easy Mode (one-click) or Expert Mode (full control)",
                        "FASTQ \u2192 BIOM + taxonomy + phylogenetic tree",
                        "Seamless handoff to downstream analysis"
                },
                Theme.PRIMARY,
                "full"
        );
        row.add(fullCard);

        downCard = buildCard(
                "Downstream Only",
                "\uD83D\uDCCA",   // bar chart emoji
                "Already have a BIOM table, taxonomy, and phylogenetic tree from a previous " +
                "EzMAP v2.0 run or another tool? Skip setup and pipeline — go straight to " +
                "interactive visualization, diversity analysis, and statistical testing " +
                "in the EzMAP v2.0 Shiny module.",
                new String[]{
                        "Upload BIOM, metadata & tree files",
                        "No QIIME2 or conda required",
                        "Interactive diversity & taxonomy plots",
                        "Differential abundance & statistical tests"
                },
                Theme.ACCENT,
                "downstream"
        );
        row.add(downCard);

        add(row);

        // ---- Preflight system check / recommended configuration ----
        JPanel sysPanel = new JPanel(new BorderLayout(0, 6));
        sysPanel.setOpaque(true);
        sysPanel.setBackground(Theme.SURFACE);
        sysPanel.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                new EmptyBorder(12, 14, 12, 14)));
        sysPanel.setAlignmentX(LEFT_ALIGNMENT);

        JLabel sysTitle = new JLabel("System check — before you start");
        sysTitle.setFont(Theme.FONT_BODY_BOLD);
        sysTitle.setForeground(Theme.INK_1);
        sysPanel.add(sysTitle, BorderLayout.NORTH);

        sysCheckLabel.setText("<html><body style='width:700px;color:#64748B'>"
                + "Checking your memory and disk space…</body></html>");
        sysCheckLabel.setFont(Theme.FONT_SMALL);
        sysCheckLabel.setForeground(Theme.INK_2);
        sysPanel.add(sysCheckLabel, BorderLayout.CENTER);

        add(sysPanel);

        // ---- Tip banner ----
        JLabel tip = new JLabel(
            "<html><body style='width:680px; font-size:11px; color:#64748B'>"
            + "<b>Tip:</b> If you've already run the upstream pipeline and want to revisit results "
            + "or re-launch downstream analysis, choose <b>Full Analysis</b> — you can skip to results "
            + "from the mode selection screen."
            + "</body></html>");
        tip.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                BorderFactory.createEmptyBorder(10, 14, 10, 14)));
        tip.setOpaque(true);
        tip.setBackground(Theme.SURFACE_2);
        add(tip);

        // ---- Bottom navigation ----
        JPanel navRow = new JPanel(new BorderLayout());
        navRow.setOpaque(false);
        navRow.setBorder(new EmptyBorder(12, 0, 0, 0));

        continueBtn.setEnabled(false);
        continueBtn.addActionListener(e -> applySelection());

        JPanel rightBtns = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        rightBtns.setOpaque(false);
        rightBtns.add(continueBtn);
        navRow.add(rightBtns, BorderLayout.EAST);

        add(navRow);
    }

    private void selectPath(String path) {
        selectedPath = path;
        continueBtn.setEnabled(true);
        updateCardBorder(fullCard, "full".equals(path), Theme.PRIMARY);
        updateCardBorder(downCard, "downstream".equals(path), Theme.ACCENT);
    }

    private void updateCardBorder(JPanel card, boolean selected, Color accent) {
        if (selected) {
            card.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createLineBorder(accent, 2, true),
                    new EmptyBorder(23, 23, 23, 23)));
        } else {
            card.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                    new EmptyBorder(24, 24, 24, 24)));
        }
    }

    private void applySelection() {
        if (selectedPath == null) return;

        if ("full".equals(selectedPath)) {
            // Full analysis: welcome → env → db → mode (then easy/expert extends it)
            wizard.setActiveFlow(
                    Arrays.asList("welcome", "env", "db", "mode"),
                    Arrays.asList("Welcome", "Environment Setup",
                                  "Database & Classifiers", "Choose Mode"));
            wizard.next();
        } else {
            // Downstream only: welcome → downstream-upload (2-step, minimal)
            wizard.setActiveFlow(
                    Arrays.asList("welcome", "downstream-upload"),
                    Arrays.asList("Welcome", "Downstream Analysis"));
            wizard.next();
        }
    }

    private JPanel buildCard(String title, String icon, String desc, String[] bullets,
                             Color accent, String pathId) {
        JPanel card = new JPanel();
        card.setLayout(new BoxLayout(card, BoxLayout.Y_AXIS));
        card.setBackground(Theme.SURFACE);
        card.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                new EmptyBorder(24, 24, 24, 24)));

        JLabel ic = new JLabel(icon);
        ic.setFont(new Font(Font.SANS_SERIF, Font.PLAIN, 36));
        ic.setAlignmentX(LEFT_ALIGNMENT);
        card.add(ic);
        card.add(Box.createVerticalStrut(8));

        JLabel t = new JLabel(title);
        t.setFont(Theme.FONT_PAGE_TITLE.deriveFont(20f));
        t.setForeground(Theme.INK_1);
        t.setAlignmentX(LEFT_ALIGNMENT);
        card.add(t);
        card.add(Box.createVerticalStrut(6));

        JLabel d = new JLabel("<html><body style='width:280px'>" + desc + "</body></html>");
        d.setFont(Theme.FONT_BODY);
        d.setForeground(Theme.INK_3);
        d.setAlignmentX(LEFT_ALIGNMENT);
        card.add(d);
        card.add(Box.createVerticalStrut(14));

        for (String b : bullets) {
            JLabel bl = new JLabel("\u2713  " + b);
            bl.setFont(Theme.FONT_SMALL);
            bl.setForeground(Theme.INK_2);
            bl.setAlignmentX(LEFT_ALIGNMENT);
            card.add(bl);
            card.add(Box.createVerticalStrut(4));
        }

        card.addMouseListener(new MouseAdapter() {
            @Override public void mouseClicked(MouseEvent e)  { selectPath(pathId); }
            @Override public void mouseEntered(MouseEvent e) {
                if (!pathId.equals(selectedPath)) {
                    card.setBorder(BorderFactory.createCompoundBorder(
                            BorderFactory.createLineBorder(accent, 2, true),
                            new EmptyBorder(23, 23, 23, 23)));
                }
            }
            @Override public void mouseExited(MouseEvent e) {
                if (!pathId.equals(selectedPath)) {
                    card.setBorder(BorderFactory.createCompoundBorder(
                            BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                            new EmptyBorder(24, 24, 24, 24)));
                }
            }
        });
        card.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        return card;
    }

    // ================================================================
    //  Preflight system check
    // ================================================================

    @Override
    public void onShown() {
        if (sysChecked) return;          // run once per session
        sysChecked = true;
        new Thread(this::runSystemCheck, "ezmap-syscheck").start();
    }

    /** Detect WSL memory + free disk (off the EDT) and render guidance. */
    private void runSystemCheck() {
        // Memory: ask WSL how much RAM it actually has — that's the figure the
        // pipeline is bound by (WSL2 caps memory below the host's physical RAM).
        int wslMb = parseMemTotalMb(captureShell("free -m"));
        int ramGb = wslMb > 0 ? Math.round(wslMb / 1024f) : -1;

        // Disk: free space on the system drive, where WSL keeps /tmp and its
        // virtual disk — the surface that fills up during classification.
        int diskGb = -1;
        try {
            long freeBytes = new File(System.getProperty("user.home")).getUsableSpace();
            if (freeBytes > 0) diskGb = (int) (freeBytes / (1024L * 1024L * 1024L));
        } catch (Exception ignore) { /* leave as -1 */ }

        final String html = buildSysCheckHtml(ramGb, diskGb);
        SwingUtilities.invokeLater(() -> sysCheckLabel.setText(html));
    }

    /** Compose the colour-coded recommendation shown on the Welcome page. */
    private String buildSysCheckHtml(int ramGb, int diskGb) {
        String ramColor, ramMsg;
        if (ramGb < 0) {
            ramColor = "#64748B";
            ramMsg = "could not detect WSL memory (is WSL installed?).";
        } else if (ramGb >= 14) {
            ramColor = "#166534";
            ramMsg = ramGb + " GB available to WSL — Easy or Expert Mode supported.";
        } else if (ramGb >= 7) {
            ramColor = "#B45309";
            ramMsg = ramGb + " GB available to WSL — Easy Mode recommended. For Expert Mode, "
                   + "use a region-specific classifier and turn on Low-memory mode.";
        } else {
            ramColor = "#B91C1C";
            ramMsg = ramGb + " GB available to WSL — low. Use Easy Mode with a V3–V4 / V4 "
                   + "classifier; full-length classifiers and Expert Mode are likely to run out of memory.";
        }

        String diskColor, diskMsg;
        if (diskGb < 0) {
            diskColor = "#64748B";
            diskMsg = "could not detect free disk space.";
        } else if (diskGb >= 30) {
            diskColor = "#166534";
            diskMsg = diskGb + " GB free on your system drive — fine, including full-length classifiers.";
        } else if (diskGb >= 12) {
            diskColor = "#B45309";
            diskMsg = diskGb + " GB free on your system drive — enough for region-specific classifiers; "
                    + "full-length needs roughly 30 GB+ free.";
        } else {
            diskColor = "#B91C1C";
            diskMsg = diskGb + " GB free on your system drive — low. WSL stores temporary files here; "
                    + "free up space or classification will fail with “No space left on device”.";
        }

        // Classifier guidance: training a Naive Bayes classifier from a full
        // reference DB needs ~16 GB+ RAM, so on smaller machines steer the user
        // to a ready-made pre-trained classifier instead of training.
        String clfColor, clfMsg;
        if (ramGb < 0) {
            clfColor = "#64748B";
            clfMsg = "training needs ~16 GB+ RAM; if memory is limited, use a pre-trained classifier.";
        } else if (ramGb >= 16) {
            clfColor = "#166534";
            clfMsg = "enough RAM to train a region-specific classifier, or use a pre-trained one.";
        } else {
            clfColor = "#B91C1C";
            clfMsg = "only " + ramGb + " GB RAM — classifier training needs ~16 GB+ and will likely crash "
                   + "(out of memory). Prefer a <b>pre-trained classifier</b> (Database &amp; Classifiers step) "
                   + "rather than training.";
        }

        return "<html><body style='width:700px;color:#334155'>"
            + "<table cellpadding='2'>"
            + "<tr><td valign='top'><b>Memory:</b>&nbsp;</td><td style='color:" + ramColor + "'>" + ramMsg + "</td></tr>"
            + "<tr><td valign='top'><b>Disk:</b>&nbsp;</td><td style='color:" + diskColor + "'>" + diskMsg + "</td></tr>"
            + "<tr><td valign='top'><b>Classifiers:</b>&nbsp;</td><td style='color:" + clfColor + "'>" + clfMsg + "</td></tr>"
            + "</table>"
            + "<div style='margin-top:6px'><b>Recommended:</b> 8 GB RAM &amp; 15 GB free disk for Easy Mode; "
            + "16 GB RAM &amp; 30 GB+ free for Expert Mode, full-length classifiers, and classifier training.</div>"
            + "<div style='margin-top:4px;color:#0B5E5D'><b>First time?</b> Run the bundled "
            + "<b>example-data</b> in <b>Easy Mode</b> to confirm your setup end-to-end before using your own data.</div>"
            + "</body></html>";
    }

    /** Parse total memory (MB) from `free -m` output; -1 if not found. */
    private static int parseMemTotalMb(String freeOutput) {
        if (freeOutput == null) return -1;
        for (String line : freeOutput.split("\\R")) {
            String t = line.trim();
            if (t.toLowerCase().startsWith("mem:")) {
                String[] parts = t.split("\\s+");
                if (parts.length >= 2) {
                    try { return Integer.parseInt(parts[1]); }
                    catch (NumberFormatException ignore) { /* fall through */ }
                }
            }
        }
        return -1;
    }

    /**
     * Run a short read-only command in WSL (or local bash on macOS/Linux) and
     * capture its output. Returns null on error. Never throws.
     */
    private static String captureShell(String bashCmd) {
        try {
            String os = System.getProperty("os.name").toLowerCase();
            ProcessBuilder pb = os.contains("win")
                    ? new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--",
                            "bash", "-lc", bashCmd)
                    : new ProcessBuilder("bash", "-lc", bashCmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            StringBuilder sb = new StringBuilder();
            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) sb.append(line).append('\n');
            }
            if (!p.waitFor(15, TimeUnit.SECONDS)) p.destroyForcibly();
            return sb.toString();
        } catch (Exception e) {
            return null;
        }
    }
}
