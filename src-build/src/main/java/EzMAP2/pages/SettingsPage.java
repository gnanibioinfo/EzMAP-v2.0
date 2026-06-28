package EzMAP2.pages;

import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.concurrent.TimeUnit;

/**
 * Lightweight Settings / Update dialog — opens from the top-bar Settings button.
 *
 * Provides maintenance functions (not first-time setup — that's DatabaseSetupPage):
 *   1. QIIME2 Environment — version display, health check, update guidance
 *   2. Storage — disk usage for databases + classifiers, clean-up buttons
 *   3. System Info — OS, Java, conda path
 *   4. Activity Log
 */
public class SettingsPage extends JDialog {

    private final LogConsole console = new LogConsole();
    private final JLabel qiimeVersionLabel = new JLabel("Checking…");
    private final JLabel condaPathLabel    = new JLabel("Checking…");
    private final JLabel diskDbLabel       = new JLabel("…");
    private final JLabel diskClLabel       = new JLabel("…");
    private final JLabel diskTotalLabel    = new JLabel("…");
    private final JLabel classifierCount   = new JLabel("…");
    private final JLabel databaseCount     = new JLabel("…");

    private static final String ENV_NAME = "EzMAP2-qiime2";

    public SettingsPage(Frame owner) {
        super(owner, "EzMAP v2.0 Settings", true);
        setSize(640, 560);
        setMinimumSize(new Dimension(540, 440));
        setLocationRelativeTo(owner);

        JPanel root = new JPanel(new BorderLayout());
        root.setBackground(Theme.BACKGROUND);

        // ---- Header ----
        JPanel header = new JPanel(new BorderLayout());
        header.setBackground(Theme.SIDEBAR_TOP);
        header.setBorder(new EmptyBorder(14, 20, 14, 20));
        JLabel title = new JLabel("\u2699  Settings & Updates");
        title.setFont(Theme.FONT_PAGE_TITLE.deriveFont(18f));
        title.setForeground(Color.WHITE);
        header.add(title, BorderLayout.WEST);
        root.add(header, BorderLayout.NORTH);

        // ---- Body ----
        JPanel body = new JPanel();
        body.setOpaque(false);
        body.setLayout(new BoxLayout(body, BoxLayout.Y_AXIS));
        body.setBorder(new EmptyBorder(14, 18, 14, 18));

        body.add(buildQiimeCard());
        body.add(Box.createVerticalStrut(12));
        body.add(buildStorageCard());
        body.add(Box.createVerticalStrut(12));
        body.add(buildSystemCard());
        body.add(Box.createVerticalStrut(12));
        body.add(buildLogCard());

        JScrollPane scroll = new JScrollPane(body,
                JScrollPane.VERTICAL_SCROLLBAR_AS_NEEDED,
                JScrollPane.HORIZONTAL_SCROLLBAR_NEVER);
        scroll.setBorder(BorderFactory.createEmptyBorder());
        scroll.setOpaque(false);
        scroll.getViewport().setOpaque(false);
        scroll.getVerticalScrollBar().setUnitIncrement(14);
        root.add(scroll, BorderLayout.CENTER);

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

    @Override
    public void setVisible(boolean visible) {
        super.setVisible(visible);
        if (visible) new Thread(this::runHealthCheck).start();
    }

    // ========================================================================
    // Cards
    // ========================================================================
    private JPanel buildQiimeCard() {
        Card card = new Card("QIIME2 Environment");

        JPanel grid = new JPanel(new GridBagLayout());
        grid.setOpaque(false);
        GridBagConstraints gc = new GridBagConstraints();
        gc.insets = new Insets(3, 0, 3, 10); gc.anchor = GridBagConstraints.WEST;

        gc.gridx = 0; gc.gridy = 0;
        grid.add(boldLabel("Version:"), gc);
        gc.gridx = 1;
        qiimeVersionLabel.setFont(Theme.FONT_BODY); qiimeVersionLabel.setForeground(Theme.INK_1);
        grid.add(qiimeVersionLabel, gc);

        gc.gridx = 0; gc.gridy = 1;
        grid.add(boldLabel("Conda Env:"), gc);
        gc.gridx = 1;
        condaPathLabel.setFont(Theme.FONT_SMALL); condaPathLabel.setForeground(Theme.INK_3);
        grid.add(condaPathLabel, gc);

        card.row(grid);
        card.gap(6);

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        btnRow.setOpaque(false);
        OutlineButton checkBtn = new OutlineButton("Refresh");
        checkBtn.addActionListener(e -> new Thread(this::runHealthCheck).start());
        btnRow.add(checkBtn);
        OutlineButton updateBtn = new OutlineButton("Update Guide");
        updateBtn.addActionListener(e -> showUpdateGuide());
        btnRow.add(updateBtn);
        card.row(btnRow);

        return card;
    }

    private JPanel buildStorageCard() {
        Card card = new Card("Storage & Resources");

        JPanel grid = new JPanel(new GridBagLayout());
        grid.setOpaque(false);
        GridBagConstraints gc = new GridBagConstraints();
        gc.insets = new Insets(3, 0, 3, 10); gc.anchor = GridBagConstraints.WEST;

        gc.gridx = 0; gc.gridy = 0;
        grid.add(boldLabel("Databases:"), gc);
        gc.gridx = 1;
        JPanel dbRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        dbRow.setOpaque(false);
        databaseCount.setFont(Theme.FONT_BODY); databaseCount.setForeground(Theme.INK_1);
        diskDbLabel.setFont(Theme.FONT_SMALL); diskDbLabel.setForeground(Theme.INK_3);
        dbRow.add(databaseCount); dbRow.add(diskDbLabel);
        grid.add(dbRow, gc);

        gc.gridx = 0; gc.gridy = 1;
        grid.add(boldLabel("Classifiers:"), gc);
        gc.gridx = 1;
        JPanel clRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        clRow.setOpaque(false);
        classifierCount.setFont(Theme.FONT_BODY); classifierCount.setForeground(Theme.INK_1);
        diskClLabel.setFont(Theme.FONT_SMALL); diskClLabel.setForeground(Theme.INK_3);
        clRow.add(classifierCount); clRow.add(diskClLabel);
        grid.add(clRow, gc);

        gc.gridx = 0; gc.gridy = 2;
        grid.add(boldLabel("Total:"), gc);
        gc.gridx = 1;
        diskTotalLabel.setFont(Theme.FONT_BODY_BOLD); diskTotalLabel.setForeground(Theme.INK_1);
        grid.add(diskTotalLabel, gc);

        card.row(grid);
        card.gap(6);

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        btnRow.setOpaque(false);
        OutlineButton openDbBtn = new OutlineButton("Open Databases Folder");
        openDbBtn.addActionListener(e -> openFolder(getDbDir()));
        btnRow.add(openDbBtn);
        OutlineButton openClBtn = new OutlineButton("Open Classifiers Folder");
        openClBtn.addActionListener(e -> openFolder(getClDir()));
        btnRow.add(openClBtn);
        card.row(btnRow);

        return card;
    }

    private JPanel buildSystemCard() {
        Card card = new Card("System Information");
        JPanel grid = new JPanel(new GridBagLayout());
        grid.setOpaque(false);
        GridBagConstraints gc = new GridBagConstraints();
        gc.insets = new Insets(3, 0, 3, 10); gc.anchor = GridBagConstraints.WEST;

        gc.gridx = 0; gc.gridy = 0;
        grid.add(boldLabel("OS:"), gc);
        gc.gridx = 1;
        grid.add(new JLabel(System.getProperty("os.name") + " " + System.getProperty("os.arch")), gc);

        gc.gridx = 0; gc.gridy = 1;
        grid.add(boldLabel("Java:"), gc);
        gc.gridx = 1;
        grid.add(new JLabel(System.getProperty("java.version") + " (" + System.getProperty("java.vendor") + ")"), gc);

        gc.gridx = 0; gc.gridy = 2;
        grid.add(boldLabel("EzMAP v2.0:"), gc);
        gc.gridx = 1;
        grid.add(new JLabel("v2.0"), gc);

        card.row(grid);
        return card;
    }

    private JPanel buildLogCard() {
        Card card = new Card("Activity Log");
        console.setPreferredSize(new Dimension(0, 120));
        card.row(console);
        return card;
    }

    // ========================================================================
    // Health check
    // ========================================================================
    private void runHealthCheck() {
        console.clear();
        console.info("Checking environment…");

        // QIIME2 version
        String ver = runShellCmd("qiime --version 2>/dev/null | head -1");
        SwingUtilities.invokeLater(() -> {
            if (ver != null && !ver.isEmpty()) {
                qiimeVersionLabel.setText(ver.trim());
                qiimeVersionLabel.setForeground(Theme.SUCCESS);
                console.ok("QIIME2: " + ver.trim());
            } else {
                qiimeVersionLabel.setText("Not found");
                qiimeVersionLabel.setForeground(Theme.DANGER);
                console.err("QIIME2 not found in " + ENV_NAME);
            }
        });

        // Conda path
        String base = runShellCmd("conda info --base 2>/dev/null");
        SwingUtilities.invokeLater(() -> {
            if (base != null && !base.isEmpty()) {
                condaPathLabel.setText(ENV_NAME + "  (" + base.trim() + ")");
                console.ok("Conda: " + base.trim());
            } else {
                condaPathLabel.setText("Conda not found");
                console.warn("Conda not found.");
            }
        });

        // Storage
        Path dbDir = getDbDir();
        Path clDir = getClDir();
        long dbSize = dirSize(dbDir);
        long clSize = dirSize(clDir);
        int dbCount = countFiles(dbDir, ".qza");
        int clCount = countFiles(clDir, ".qza");

        SwingUtilities.invokeLater(() -> {
            databaseCount.setText(dbCount + " file(s)");
            diskDbLabel.setText("(" + humanSize(dbSize) + ")");
            classifierCount.setText(clCount + " classifier(s)");
            diskClLabel.setText("(" + humanSize(clSize) + ")");
            diskTotalLabel.setText(humanSize(dbSize + clSize));
        });

        console.ok("Storage: " + humanSize(dbSize) + " databases, " + humanSize(clSize) + " classifiers");
        console.ok("Check complete.");
    }

    // ========================================================================
    // Dialogs
    // ========================================================================
    private void showUpdateGuide() {
        console.info("QIIME2 update commands:");
        console.info("  Minor update: conda activate " + ENV_NAME + " && conda update --all");
        console.info("  Full upgrade: conda env remove -n " + ENV_NAME + " && re-run install.sh");

        JOptionPane.showMessageDialog(this,
                "<html><body style='width:440px'>"
                + "<b>Update QIIME2</b><br><br>"
                + "<b>Minor update</b> (same version):<br>"
                + "<code>conda activate " + ENV_NAME + "<br>conda update --all</code><br><br>"
                + "<b>Major upgrade</b> (new version):<br>"
                + "<code>conda env remove -n " + ENV_NAME + "</code><br>"
                + "Then re-run the Environment Setup page in EzMAP v2.0.<br><br>"
                + "<b>Note:</b> After a major QIIME2 upgrade, re-train your classifiers — "
                + "they are tied to the scikit-learn version."
                + "</body></html>",
                "Update Guide", JOptionPane.INFORMATION_MESSAGE);
    }

    private void openFolder(Path dir) {
        try {
            Files.createDirectories(dir);
            Desktop.getDesktop().open(dir.toFile());
        } catch (Exception e) {
            console.warn("Could not open folder: " + dir);
        }
    }

    // ========================================================================
    // Shell helper
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

    private String runShellCmd(String cmd) {
        try {
            String os = System.getProperty("os.name").toLowerCase();
            String fullCmd = condaInitPreamble() + cmd;
            ProcessBuilder pb;
            if (os.contains("win")) {
                pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc", fullCmd);
            } else {
                pb = new ProcessBuilder("bash", "-lc", fullCmd);
            }
            pb.redirectErrorStream(true);
            Process p = pb.start();
            byte[] raw = p.getInputStream().readAllBytes();
            boolean done = p.waitFor(15, TimeUnit.SECONDS);
            if (!done) { p.destroyForcibly(); return null; }
            return new String(raw, StandardCharsets.UTF_8).trim();
        } catch (Exception e) { return null; }
    }

    // ========================================================================
    // Utility
    // ========================================================================
    private Path getDbDir() { return Paths.get(System.getProperty("user.home"), "ezmap2-databases"); }
    private Path getClDir() { return Paths.get(System.getProperty("user.home"), "ezmap2-classifiers"); }

    private static long dirSize(Path dir) {
        if (!Files.isDirectory(dir)) return 0;
        try {
            return Files.walk(dir).filter(Files::isRegularFile)
                    .mapToLong(p -> { try { return Files.size(p); } catch (IOException e) { return 0; } })
                    .sum();
        } catch (IOException e) { return 0; }
    }

    private static int countFiles(Path dir, String suffix) {
        if (!Files.isDirectory(dir)) return 0;
        try {
            return (int) Files.list(dir).filter(p -> p.toString().endsWith(suffix)).count();
        } catch (IOException e) { return 0; }
    }

    private static String humanSize(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return String.format("%.1f KB", bytes / 1024.0);
        if (bytes < 1024 * 1024 * 1024) return String.format("%.1f MB", bytes / (1024.0 * 1024));
        return String.format("%.2f GB", bytes / (1024.0 * 1024 * 1024));
    }

    private static JLabel boldLabel(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_BODY_BOLD);
        l.setForeground(Theme.INK_2);
        return l;
    }
}
