package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import java.awt.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/**
 * Downstream-only entry point: user uploads BIOM, metadata, and tree
 * then launches the Shiny app directly — no QIIME2 or conda needed.
 */
public class DownstreamUploadPage extends BasePage {

    private final WizardController wizard;

    private final DirectoryPicker biomPicker = new DirectoryPicker(
            "feature-table-tax.biom or feature-table.biom", f -> refreshLaunchState(), true);
    private final DirectoryPicker metaPicker = new DirectoryPicker(
            "metadata.tsv", f -> refreshLaunchState(), true);
    private final DirectoryPicker treePicker = new DirectoryPicker(
            "(optional) rooted-tree.nwk", f -> {}, true);
    private final DirectoryPicker bundlePicker = new DirectoryPicker(
            "Or select EzMAP v2 bundle folder (auto-fills above)", f -> onBundleSelected(f));

    private final PrimaryButton launchBtn = new PrimaryButton("Launch Downstream Analysis  \u2192");
    private final OutlineButton stopBtn  = new OutlineButton("Stop Shiny");
    private final JLabel        statusLabel = new JLabel(" ");
    private final LogConsole    console = new LogConsole();

    private volatile Process shinyProcess;

    public DownstreamUploadPage(WizardController wizard) {
        super("Downstream Analysis",
              "Upload your processed data files to launch the interactive EzMAP v2 " +
              "Shiny module for diversity analysis, taxonomy visualization, and statistical testing.");
        this.wizard = wizard;

        // ---- Bundle shortcut card ----
        Card bundleCard = new Card("Quick Load — EzMAP v2 Bundle");
        bundleCard.row(caption(
                "If you have an EzMAP v2 output folder (from a previous run), select it here and " +
                "all files will be auto-detected:"));
        bundleCard.gap(6);
        bundleCard.row(bundlePicker);
        add(bundleCard);

        // ---- Individual file pickers card ----
        Card filesCard = new Card("Data Files");

        filesCard.row(caption("BIOM table (required) — .biom file with ASV abundances, ideally with taxonomy"))
                 .row(biomPicker).gap(8);
        filesCard.row(caption("Sample metadata (required) — .tsv with sample IDs matching the BIOM table"))
                 .row(metaPicker).gap(8);
        filesCard.row(caption("Phylogenetic tree (optional) — .nwk for UniFrac and phylogenetic diversity"))
                 .row(treePicker).gap(12);

        InfoBanner formatNote = new InfoBanner(InfoBanner.Kind.INFO,
                "Supported formats",
                "BIOM v2.1 (.biom) with or without taxonomy metadata. " +
                "Metadata must be tab-separated (.tsv) with 'sample-id' or '#SampleID' as the first column. " +
                "Tree in Newick format (.nwk).");
        filesCard.row(formatNote);

        add(filesCard);

        // ---- Launch card ----
        Card launchCard = new Card("Launch");
        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 12, 0));
        btnRow.setOpaque(false);
        btnRow.add(launchBtn);
        btnRow.add(stopBtn);
        statusLabel.setFont(Theme.FONT_BODY);
        btnRow.add(statusLabel);
        launchCard.row(btnRow).gap(8);

        console.setPreferredSize(new Dimension(0, 160));
        launchCard.row(console);
        add(launchCard);

        // ---- Wiring ----
        launchBtn.setEnabled(false);
        stopBtn.setEnabled(false);
        launchBtn.addActionListener(e -> launchShiny());
        stopBtn.addActionListener(e -> stopShiny());
    }

    // ==================================================================
    //  Bundle auto-detection
    // ==================================================================

    private void onBundleSelected(File dir) {
        if (dir == null) return;

        // If user picked a file (e.g. zip), use its parent
        File folder = dir.isDirectory() ? dir : dir.getParentFile();
        if (folder == null || !folder.isDirectory()) return;

        // Look for bundle/ subfolder first (EzMAP2 output structure)
        File bundleSub = new File(folder, "bundle");
        File searchDir = bundleSub.isDirectory() ? bundleSub : folder;

        // Auto-detect files
        File biom = findFile(searchDir, "feature-table-tax.biom", "feature-table.biom", "table.biom");
        File meta = findFile(searchDir, "metadata.tsv", "sample-metadata.tsv");
        File tree = findFile(searchDir, "rooted-tree.nwk", "tree.nwk");

        // Also check parent for metadata (often kept alongside bundle/)
        if (meta == null) meta = findFile(folder, "metadata.tsv", "sample-metadata.tsv");

        if (biom != null) biomPicker.setPath(biom.getAbsolutePath());
        if (meta != null) metaPicker.setPath(meta.getAbsolutePath());
        if (tree != null) treePicker.setPath(tree.getAbsolutePath());

        if (biom != null) {
            statusLabel.setText("<html><span style='color:#16A34A'>\u2713 Bundle loaded — " +
                    (biom != null ? "BIOM" : "") +
                    (meta != null ? ", metadata" : "") +
                    (tree != null ? ", tree" : "") +
                    " detected</span></html>");
        } else {
            statusLabel.setText("<html><span style='color:#D97706'>\u26A0 No BIOM file found in this folder</span></html>");
        }
        refreshLaunchState();
    }

    private File findFile(File dir, String... names) {
        if (dir == null || !dir.isDirectory()) return null;
        for (String name : names) {
            File f = new File(dir, name);
            if (f.isFile()) return f;
        }
        return null;
    }

    // ==================================================================
    //  State
    // ==================================================================

    private void refreshLaunchState() {
        launchBtn.setEnabled(!biomPicker.isEmpty() && !metaPicker.isEmpty());
    }

    // ==================================================================
    //  Launch Shiny
    // ==================================================================

    private void stopShiny() {
        if (shinyProcess != null && shinyProcess.isAlive()) {
            shinyProcess.destroy();
            console.warn("Stopping Shiny server\u2026");
        }
    }

    private void launchShiny() {
        launchBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        statusLabel.setText("<html><span style='color:#64748B'>Launching Shiny app\u2026</span></html>");
        console.clear();
        console.info("Starting EzMAP v2 Downstream Analysis (Shiny)\u2026");

        final String biom = biomPicker.getPath();
        final String meta = metaPicker.getPath();
        final String tree = treePicker.isEmpty() ? "" : treePicker.getPath();

        new Thread(() -> runShiny(biom, meta, tree)).start();
    }

    private void runShiny(String biom, String meta, String tree) {
        try {
            // Step 1: Auto-install missing R packages
            ensureRPackages(console, statusLabel);

            // Step 2: Locate the Shiny app directory
            String projectDir = System.getProperty("user.dir");
            File shinyApp = locateShinyApp(projectDir);

            if (shinyApp == null) {
                SwingUtilities.invokeLater(() -> {
                    console.err("Shiny app directory not found. Expected: EzMAPv2-downstream/");
                    console.err("Searched: " + new File(projectDir).getParent());
                    statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Shiny app not found</span></html>");
                    launchBtn.setEnabled(true);
                });
                return;
            }

            final File appDir = shinyApp;
            SwingUtilities.invokeLater(() ->
                    console.info("Shiny app: " + appDir.getAbsolutePath()));

            // Write a temp .R launcher script — avoids all quoting issues across OSes
            String osName = System.getProperty("os.name").toLowerCase();
            ProcessBuilder pb = buildShinyProcess(osName, appDir, biom, meta, tree);

            pb.redirectErrorStream(true);

            SwingUtilities.invokeLater(() -> console.info("Starting R Shiny server\u2026"));

            shinyProcess = pb.start();

            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(shinyProcess.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                    final String s = line;
                    SwingUtilities.invokeLater(() -> {
                        console.info(s);
                        if (s.contains("Listening on")) {
                            statusLabel.setText("<html><span style='color:#16A34A'>\u2713 Shiny is running — " +
                                    s.substring(s.indexOf("http")) + "</span></html>");
                        }
                    });
                }
            }

            int exit = shinyProcess.waitFor();
            SwingUtilities.invokeLater(() -> {
                if (exit == 0) {
                    console.ok("Shiny app stopped.");
                } else {
                    console.warn("Shiny exited with code " + exit);
                }
                statusLabel.setText(" ");
                launchBtn.setEnabled(true);
                stopBtn.setEnabled(false);
            });

        } catch (Exception ex) {
            SwingUtilities.invokeLater(() -> {
                console.err("Failed to launch Shiny: " + ex.getMessage());
                statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Launch failed</span></html>");
                launchBtn.setEnabled(true);
                stopBtn.setEnabled(false);
            });
        }
    }

    /** Locate the EzMAPv2-downstream Shiny app directory. */
    private File locateShinyApp(String projectDir) {
        // Resolve JAR location so we find the Shiny app bundled with this build
        String jarDir = null;
        try {
            String jarPath = DownstreamUploadPage.class.getProtectionDomain()
                    .getCodeSource().getLocation().getPath();
            // Decode URL-encoded spaces (%20 etc.) for Windows paths
            jarDir = new File(java.net.URLDecoder.decode(jarPath, "UTF-8")).getParent();
        } catch (Exception ignored) {}

        String[] tries = {
                // 1. Same folder as the JAR (highest priority — bundled distribution)
                jarDir != null ? jarDir + File.separator + "EzMAPv2-downstream" : null,
                // 2. Inside the working directory
                projectDir + File.separator + "EzMAPv2-downstream",
                // 3. Sibling of working directory
                new File(projectDir).getParent() + File.separator + "EzMAPv2-downstream",
                // 4. Grandparent
                new File(projectDir).getParentFile().getParent() + File.separator + "EzMAPv2-downstream"
        };
        for (String path : tries) {
            if (path == null) continue;
            File f = new File(path);
            if (f.isDirectory()) return f;
        }
        return null;
    }

    // ==================================================================
    //  Auto-install R packages (shared logic)
    // ==================================================================

    /**
     * Locate the install_r_packages.R script relative to the project dir.
     * Searches: scripts/, ../scripts/, ../../scripts/
     */
    static File locateInstallerScript(String projectDir) {
        String[] tries = {
                projectDir + File.separator + "scripts" + File.separator + "install_r_packages.R",
                new File(projectDir).getParent() + File.separator + "scripts" + File.separator + "install_r_packages.R",
                projectDir + File.separator + "install_r_packages.R",
        };
        // Also check grandparent
        File parent = new File(projectDir).getParentFile();
        if (parent != null && parent.getParentFile() != null) {
            tries = java.util.Arrays.copyOf(tries, tries.length + 1);
            tries[tries.length - 1] = parent.getParent() + File.separator + "scripts" + File.separator + "install_r_packages.R";
        }
        for (String path : tries) {
            File f = new File(path);
            if (f.isFile()) return f;
        }
        return null;
    }

    /**
     * Run the R package installer script and stream output to a LogConsole.
     * Returns true if the installer completed (exit 0), false otherwise.
     * If the installer script is not found, returns true (skip check).
     */
    static boolean ensureRPackages(LogConsole console, JLabel statusLabel) {
        String projectDir = System.getProperty("user.dir");
        File installerScript = locateInstallerScript(projectDir);

        if (installerScript == null) {
            SwingUtilities.invokeLater(() ->
                    console.warn("install_r_packages.R not found — skipping package check."));
            return true;
        }

        SwingUtilities.invokeLater(() -> {
            console.info("Checking R packages (auto-install if missing)\u2026");
            statusLabel.setText("<html><span style='color:#64748B'>Checking R packages\u2026</span></html>");
        });

        try {
            String osName = System.getProperty("os.name").toLowerCase();
            boolean isWindows = osName.contains("win");

            ProcessBuilder pb;
            if (isWindows) {
                boolean hasNativeR = isNativeWindowsRAvailable();
                if (hasNativeR) {
                    pb = new ProcessBuilder("Rscript.exe", installerScript.getAbsolutePath());
                } else if (isWslRAvailable()) {
                    String wslPath = toWsl(installerScript.getAbsolutePath());
                    String cmd = condaInitPreamble() + "Rscript " + wslPath;
                    pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--", "bash", "-lc", cmd);
                } else {
                    // No R available at all — skip check, Shiny launch will fail with a clear error
                    SwingUtilities.invokeLater(() ->
                            console.warn("Rscript not found — skipping package check."));
                    return true;
                }
            } else {
                // macOS / Linux
                pb = new ProcessBuilder("bash", "-lc",
                        "Rscript " + installerScript.getAbsolutePath());
            }

            pb.redirectErrorStream(true);
            Process proc = pb.start();

            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(proc.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                    final String s = line;
                    SwingUtilities.invokeLater(() -> {
                        if (s.contains("[OK]")) {
                            console.ok(s);
                        } else if (s.contains("[WARN]")) {
                            console.warn(s);
                        } else if (s.contains("[INSTALL]") || s.contains("Installing")) {
                            console.info(s);
                        } else {
                            console.info(s);
                        }
                    });
                }
            }

            boolean finished = proc.waitFor(600, java.util.concurrent.TimeUnit.SECONDS);
            if (!finished) {
                proc.destroyForcibly();
                SwingUtilities.invokeLater(() ->
                        console.warn("Package installation timed out (10 min). Proceeding anyway\u2026"));
                return true;
            }

            int exit = proc.exitValue();
            if (exit == 0) {
                SwingUtilities.invokeLater(() ->
                        console.ok("R packages ready."));
                return true;
            } else {
                SwingUtilities.invokeLater(() ->
                        console.warn("Package installer exited with code " + exit + ". Trying to launch anyway\u2026"));
                return true; // still try to launch — partial functionality is better
            }

        } catch (Exception ex) {
            SwingUtilities.invokeLater(() ->
                    console.warn("Package check failed: " + ex.getMessage() + ". Proceeding\u2026"));
            return true;
        }
    }

    // ==================================================================
    //  Cross-platform Shiny launcher (shared logic)
    // ==================================================================

    /**
     * Build a ProcessBuilder that launches the Shiny app on any OS.
     * Writes a temp .R script to avoid all shell quoting issues.
     *
     * Windows:
     *   1. Try WSL R (conda env or system R inside Ubuntu WSL)
     *   2. Fallback: native Windows Rscript.exe (e.g. from RStudio/CRAN)
     *
     * macOS:
     *   bash -lc "Rscript /tmp/ezmap2_launch_xxx.R"
     *   (login shell ensures conda/Homebrew R is on PATH)
     *
     * Linux:
     *   bash -lc "Rscript /tmp/ezmap2_launch_xxx.R"
     *   (login shell ensures conda/system R is on PATH)
     */
    static ProcessBuilder buildShinyProcess(String osName, File appDir,
                                             String biom, String meta, String tree) throws IOException {
        boolean isWindows = osName.contains("win");

        // Detect whether to use native Windows R or WSL R.
        // Prefer native R (from RStudio / CRAN) because it typically has
        // up-to-date packages (bslib, shiny) needed for the modern UI.
        // WSL R (installed via conda for QIIME2) often has older packages
        // that fall back to Bootstrap 3, producing the old design.
        boolean useWsl = false;
        boolean hasNativeR = false;

        if (isWindows) {
            hasNativeR = isNativeWindowsRAvailable();
            if (!hasNativeR) {
                useWsl = isWslRAvailable();
            }
        }

        // Determine if paths need /mnt/ conversion (only for WSL)
        boolean convertPaths = isWindows && useWsl;

        // Build R script content
        StringBuilder rScript = new StringBuilder();
        rScript.append("# EzMAP v2 Downstream Launcher (auto-generated)\n");

        if (biom != null && !biom.isEmpty()) {
            rScript.append("Sys.setenv(EZMAP2_BIOM = '")
                   .append(rPath(biom, convertPaths)).append("')\n");
        }
        if (meta != null && !meta.isEmpty()) {
            rScript.append("Sys.setenv(EZMAP2_METADATA = '")
                   .append(rPath(meta, convertPaths)).append("')\n");
        }
        if (tree != null && !tree.isEmpty()) {
            rScript.append("Sys.setenv(EZMAP2_TREE = '")
                   .append(rPath(tree, convertPaths)).append("')\n");
        }
        rScript.append("shiny::runApp('")
               .append(rPath(appDir.getAbsolutePath(), convertPaths))
               .append("', launch.browser = TRUE)\n");

        // Write temp .R file
        File tempR = File.createTempFile("ezmap2_launch_", ".R");
        tempR.deleteOnExit();
        Files.write(tempR.toPath(), rScript.toString().getBytes(StandardCharsets.UTF_8));

        ProcessBuilder pb;

        if (isWindows && useWsl) {
            // --- Windows + WSL R ---
            String wslTempPath = toWsl(tempR.getAbsolutePath());
            String cmd = condaInitPreamble() + "Rscript " + wslTempPath;
            pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--", "bash", "-lc", cmd);
            pb.directory(appDir);

        } else if (isWindows && hasNativeR) {
            // --- Windows native Rscript.exe ---
            // R script uses Windows paths (forward slashes but no /mnt/)
            pb = new ProcessBuilder("Rscript.exe", tempR.getAbsolutePath());
            pb.directory(appDir);

        } else if (isWindows) {
            // --- Windows, no R found: try WSL anyway (will show error) ---
            String wslTempPath = toWsl(tempR.getAbsolutePath());
            String cmd = condaInitPreamble() + "Rscript " + wslTempPath;
            pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--", "bash", "-lc", cmd);
            pb.directory(appDir);

        } else {
            // --- macOS / Linux ---
            // bash -l loads login profile, so conda R / Homebrew R / system R is found
            pb = new ProcessBuilder("bash", "-lc",
                    "Rscript " + tempR.getAbsolutePath());
            pb.directory(appDir);
        }

        return pb;
    }

    // ==================================================================
    //  R detection helpers
    // ==================================================================

    /** Check if Rscript is available inside WSL Ubuntu. */
    private static boolean isWslRAvailable() {
        try {
            ProcessBuilder pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--",
                    "bash", "-lc", condaInitPreamble() + "command -v Rscript");
            pb.redirectErrorStream(true);
            Process p = pb.start();
            byte[] out = p.getInputStream().readAllBytes();
            boolean ok = p.waitFor(8, java.util.concurrent.TimeUnit.SECONDS);
            if (!ok) { p.destroyForcibly(); return false; }
            return p.exitValue() == 0 && new String(out).trim().contains("Rscript");
        } catch (Exception e) {
            return false;
        }
    }

    /** Check if Rscript.exe exists on the Windows PATH or common install locations. */
    private static boolean isNativeWindowsRAvailable() {
        try {
            ProcessBuilder pb = new ProcessBuilder("where.exe", "Rscript.exe");
            pb.redirectErrorStream(true);
            Process p = pb.start();
            p.getInputStream().readAllBytes();
            boolean ok = p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
            if (!ok) { p.destroyForcibly(); return false; }
            return p.exitValue() == 0;
        } catch (Exception e) {
            return false;
        }
    }

    // ==================================================================
    //  Path helpers
    // ==================================================================

    /** Convert a path to R-safe format (forward slashes, escaped single quotes). */
    private static String rPath(String path, boolean toWslPath) {
        String p = path.replace("\\", "/");
        if (toWslPath && p.length() >= 2 && p.charAt(1) == ':') {
            p = "/mnt/" + Character.toLowerCase(p.charAt(0)) + p.substring(2);
        }
        return p.replace("'", "\\'");
    }

    private static String toWsl(String winPath) {
        if (winPath == null || winPath.isEmpty()) return winPath;
        String p = winPath.replace("\\", "/");
        if (p.length() >= 2 && p.charAt(1) == ':') {
            return "/mnt/" + Character.toLowerCase(p.charAt(0)) + p.substring(2);
        }
        return p;
    }

    /**
     * Preamble that sources conda.sh from common install locations,
     * so Rscript (installed via conda) is on the PATH inside WSL.
     */
    private static String condaInitPreamble() {
        return "for d in \"$HOME/miniconda3\" \"$HOME/miniforge3\" \"$HOME/mambaforge\" "
                + "\"$HOME/anaconda3\" \"/opt/conda\"; do "
                + "if [ -f \"$d/etc/profile.d/conda.sh\" ]; then "
                + "source \"$d/etc/profile.d/conda.sh\"; break; fi; done; ";
    }

    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }
}
