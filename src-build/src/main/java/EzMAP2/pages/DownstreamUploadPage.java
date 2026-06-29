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
            "Or select EzMAP v2.0 bundle folder (auto-fills above)", f -> onBundleSelected(f));

    private final PrimaryButton launchBtn = new PrimaryButton("Launch Downstream Analysis  \u2192");
    private final OutlineButton stopBtn  = new OutlineButton("Stop Shiny");
    private final JLabel        statusLabel = new JLabel(" ");
    private final LogConsole    console = new LogConsole();

    private volatile Process shinyProcess;
    private volatile boolean userStopped = false;   // true while a user-initiated Stop is in progress

    public DownstreamUploadPage(WizardController wizard) {
        super("Downstream Analysis",
              "Upload your processed data files to launch the interactive EzMAP v2.0 " +
              "Shiny module for diversity analysis, taxonomy visualization, and statistical testing.");
        this.wizard = wizard;

        // ---- Bundle shortcut card ----
        Card bundleCard = new Card("Quick Load — EzMAP v2.0 Bundle");
        bundleCard.row(caption(
                "If you have an EzMAP v2.0 output folder (from a previous run), select it here and " +
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
        Process p = shinyProcess;
        if (p != null) {
            userStopped = true;     // tell the launch thread this exit is expected
            console.warn("Stopping Shiny server\u2026");
            killShinyTree(p);
            shinyProcess = null;
            console.ok("Shiny server stopped. (You can close the browser tab \u2014 it "
                    + "shows a grey \u201cdisconnected\u201d screen once the server stops.)");
        }
        // Reset the UI immediately so the user can relaunch even if the
        // process tree took a moment to die.
        SwingUtilities.invokeLater(() -> {
            refreshLaunchState();
            stopBtn.setEnabled(false);
            statusLabel.setText(" ");
        });
    }

    /**
     * Forcibly terminate a Shiny process and ALL of its children so the port is
     * released and the app can be relaunched cleanly.
     *
     * The previous code only called destroy() on the direct process. That left
     * orphaned R / Rscript processes running \u2014 especially when launched through
     * WSL, where the real R process lives inside the WSL VM and is not a Windows
     * child of wsl.exe \u2014 so the server never actually stopped, waitFor() never
     * returned, and the Launch button stayed disabled (the reviewer's "could not
     * stop the Shiny server or relaunch" issue).
     */
    static void killShinyTree(Process p) {
        if (p == null) return;
        String os = System.getProperty("os.name").toLowerCase();
        try {
            if (os.contains("win")) {
                // 1. Kill the native Windows process tree (Rscript.exe + child R,
                //    or the wsl.exe relay) by PID.
                try {
                    new ProcessBuilder("taskkill", "/F", "/T", "/PID",
                            Long.toString(p.pid()))
                            .redirectErrorStream(true).start()
                            .waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
                } catch (Exception ignored) {}
                // 2. The Shiny server may run INSIDE WSL (not a Windows child of
                //    wsl.exe). Our launcher script is named ezmap2_launch_*.R, so
                //    this pkill targets only our app and nothing else.
                try {
                    new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc",
                            "pkill -f ezmap2_launch")
                            .redirectErrorStream(true).start()
                            .waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
                } catch (Exception ignored) {}
            } else {
                // macOS / Linux: kill descendants first, then the process itself.
                p.descendants().forEach(ProcessHandle::destroyForcibly);
            }
        } catch (Exception ignored) {
        } finally {
            p.destroyForcibly();
        }
    }

    private void launchShiny() {
        launchBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        statusLabel.setText("<html><span style='color:#64748B'>Launching Shiny app\u2026</span></html>");
        console.clear();
        console.info("Starting EzMAP v2.0 Downstream Analysis (Shiny)\u2026");

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

            Process proc = pb.start();
            shinyProcess = proc;

            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(proc.getInputStream(), StandardCharsets.UTF_8))) {
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

            int exit = proc.waitFor();
            boolean stopped = userStopped;   // was this exit caused by the Stop button?
            userStopped = false;
            SwingUtilities.invokeLater(() -> {
                if (exit == 0 || stopped) {
                    console.ok("Shiny server stopped.");
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
        String name = "install_r_packages.R";
        String sub = "scripts" + File.separator + name;
        java.util.List<File> tries = new java.util.ArrayList<>();
        // Next to the JAR first — works no matter what the working directory is.
        try {
            String jarPath = DownstreamUploadPage.class.getProtectionDomain()
                    .getCodeSource().getLocation().getPath();
            File jarDir = new File(java.net.URLDecoder.decode(jarPath, "UTF-8")).getParentFile();
            if (jarDir != null) {
                tries.add(new File(jarDir, sub));
                File p1 = jarDir.getParentFile();
                if (p1 != null) {
                    tries.add(new File(p1, sub));
                    File p2 = p1.getParentFile();
                    if (p2 != null) tries.add(new File(p2, sub));
                }
            }
        } catch (Exception ignored) {}
        // Then relative to the working directory.
        tries.add(new File(projectDir, sub));
        tries.add(new File(projectDir, name));
        File parent = new File(projectDir).getParentFile();
        if (parent != null) {
            tries.add(new File(parent, sub));
            if (parent.getParentFile() != null) tries.add(new File(parent.getParentFile(), sub));
        }
        for (File f : tries) {
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

        final Runnable showInstallBanner = () -> SwingUtilities.invokeLater(() -> {
            console.info("First launch: installing the R packages required for the "
                    + "downstream analyses. This one-time setup can take 10-30 "
                    + "minutes; later launches start instantly.");
            statusLabel.setText("<html><span style='color:#64748B'>Installing required R "
                    + "packages (first launch only \u2014 please wait)\u2026</span></html>");
        });

        try {
            String osName = System.getProperty("os.name").toLowerCase();
            boolean isWindows = osName.contains("win");

            ProcessBuilder pb;
            if (isWindows) {
                RChoice rc = chooseR(true);

                // If the chosen R already has the packages (e.g. the WSL conda R
                // populated by install.sh), skip the install entirely.
                if (rc.packagesReady) {
                    final String which = rc.useWsl ? "WSL R" : "native Windows R";
                    SwingUtilities.invokeLater(() -> {
                        console.ok("Required R packages already present (" + which
                                + ") — skipping install.");
                        statusLabel.setText("<html><span style='color:#64748B'>R packages "
                                + "ready</span></html>");
                    });
                    return true;
                }

                showInstallBanner.run();

                if (rc.hasNativeR) {
                    final String rsPath = rc.nativeRscript;
                    SwingUtilities.invokeLater(() ->
                            console.info("Using R: " + rsPath));
                    pb = new ProcessBuilder(rc.nativeRscript, installerScript.getAbsolutePath());
                } else if (rc.useWsl) {
                    String wslPath = toWsl(installerScript.getAbsolutePath());
                    String cmd = condaInitPreamble() + "Rscript " + wslPath;
                    pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc", cmd);
                } else {
                    // No R available at all — skip check, Shiny launch will fail with a clear error
                    SwingUtilities.invokeLater(() ->
                            console.warn("Rscript not found — skipping package check."));
                    return true;
                }
            } else {
                // macOS / Linux
                showInstallBanner.run();
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

        // Decide which R to launch on. chooseR() prefers an R that already has
        // the packages (native first, for the modern UI; otherwise the WSL conda
        // R populated by install.sh) so a fresh machine never does a redundant
        // install. Must match the R that ensureRPackages() used.
        boolean useWsl = false;
        boolean hasNativeR = false;
        String nativeRscript = null;

        if (isWindows) {
            RChoice rc = chooseR(true);
            useWsl = rc.useWsl;
            hasNativeR = rc.hasNativeR;
            nativeRscript = rc.nativeRscript;
        }

        // Determine if paths need /mnt/ conversion (only for WSL)
        boolean convertPaths = isWindows && useWsl;

        // Build R script content
        StringBuilder rScript = new StringBuilder();
        rScript.append("# EzMAP v2.0 Downstream Launcher (auto-generated)\n");

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
            pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc", cmd);
            pb.directory(appDir);

        } else if (isWindows && hasNativeR) {
            // --- Windows native Rscript.exe (resolved full path, not PATH-dependent) ---
            // R script uses Windows paths (forward slashes but no /mnt/)
            pb = new ProcessBuilder(nativeRscript, tempR.getAbsolutePath());
            pb.directory(appDir);

        } else if (isWindows) {
            // --- Windows, no R found: try WSL anyway (will show error) ---
            String wslTempPath = toWsl(tempR.getAbsolutePath());
            String cmd = condaInitPreamble() + "Rscript " + wslTempPath;
            pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc", cmd);
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

    // ------------------------------------------------------------------
    //  Smart R selection: prefer an R that already has the packages so a
    //  fresh machine never does a redundant install.
    //    1. native Windows R with packages   (best UI, instant)
    //    2. WSL conda R with packages         (populated by install.sh, instant)
    //    3. WSL conda R, install needed       (the managed env — completes fastest)
    //    4. native Windows R, install needed  (from scratch, into writable user lib)
    // ------------------------------------------------------------------
    static final class RChoice {
        final boolean useWsl;        // run through the WSL conda R
        final boolean hasNativeR;    // run through native Windows Rscript.exe
        final String  nativeRscript; // full path when hasNativeR is true
        final boolean packagesReady; // the chosen R already has the core packages
        RChoice(boolean useWsl, boolean hasNativeR, String nativeRscript, boolean packagesReady) {
            this.useWsl = useWsl;
            this.hasNativeR = hasNativeR;
            this.nativeRscript = nativeRscript;
            this.packagesReady = packagesReady;
        }
    }

    private static RChoice cachedChoice;

    /** Decide once which R to use; cached for the rest of the session. */
    static synchronized RChoice chooseR(boolean isWindows) {
        if (cachedChoice != null) return cachedChoice;
        if (!isWindows) {
            cachedChoice = new RChoice(false, false, null, false);
            return cachedChoice;
        }
        String nativeRscript = resolveWindowsRscript();
        boolean wslAvail = isWslRAvailable();
        if (nativeRscript != null && rHasCorePackages(nativeRscript, false)) {
            cachedChoice = new RChoice(false, true, nativeRscript, true);   // 1 native, ready
        } else if (wslAvail && rHasCorePackages(null, true)) {
            cachedChoice = new RChoice(true, false, null, true);            // 2 WSL, ready
        } else if (wslAvail) {
            cachedChoice = new RChoice(true, false, null, false);           // 3 WSL, install
        } else if (nativeRscript != null) {
            cachedChoice = new RChoice(false, true, nativeRscript, false);  // 4 native, install
        } else {
            cachedChoice = new RChoice(false, false, null, false);          // no R
        }
        return cachedChoice;
    }

    /** True if the given R already has the core downstream packages installed. */
    private static boolean rHasCorePackages(String nativeRscript, boolean wsl) {
        // Check a representative spread (UI + core + a Bioconductor + an ML/stats
        // package) so "ready" reliably means install.sh's R setup completed, and
        // we only skip the installer when the whole set is genuinely present.
        final String expr =
                "cat(all(vapply(c('shiny','bslib','phyloseq','DESeq2','randomForest','vegan'),"
              + "function(p) nzchar(system.file(package=p)), logical(1))))";
        try {
            ProcessBuilder pb;
            if (wsl) {
                pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc",
                        condaInitPreamble() + "Rscript -e \"" + expr + "\"");
            } else {
                pb = new ProcessBuilder(nativeRscript, "-e", expr);
            }
            pb.redirectErrorStream(true);
            Process p = pb.start();
            byte[] out = p.getInputStream().readAllBytes();
            boolean ok = p.waitFor(30, java.util.concurrent.TimeUnit.SECONDS);
            if (!ok) { p.destroyForcibly(); return false; }
            return new String(out, StandardCharsets.UTF_8).contains("TRUE");
        } catch (Exception e) {
            return false;
        }
    }

    /** Check if Rscript is available inside WSL Ubuntu. */
    private static boolean isWslRAvailable() {
        try {
            ProcessBuilder pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--",
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

    /** Check if a native Windows Rscript.exe can be located. */
    private static boolean isNativeWindowsRAvailable() {
        return resolveWindowsRscript() != null;
    }

    // ------------------------------------------------------------------
    //  Robust Rscript.exe resolution on Windows
    //
    //  R's Windows installer does NOT add R to the PATH by default, so
    //  "where.exe Rscript.exe" fails on most fresh installs (this was the
    //  cause of the reviewer's "could not find Rscript" error). In addition
    //  to PATH, we probe the standard install directories, the R_HOME
    //  environment variable and the Windows registry, returning the full
    //  path to the newest Rscript.exe found.
    // ------------------------------------------------------------------
    private static volatile String cachedRscriptPath;
    private static volatile boolean rscriptResolved;

    /** Return the full path to Rscript.exe on Windows, or null if none found. */
    static String resolveWindowsRscript() {
        if (rscriptResolved) return cachedRscriptPath;
        String found = null;
        try {
            // 1. Already on PATH
            found = whereRscript();
            // 2. R_HOME environment variable
            if (found == null) {
                String rHome = System.getenv("R_HOME");
                found = firstExisting(
                        rHome == null ? null : rHome + "\\bin\\x64\\Rscript.exe",
                        rHome == null ? null : rHome + "\\bin\\Rscript.exe");
            }
            // 3. Standard install roots — newest R-x.y.z wins
            if (found == null) {
                String pf   = System.getenv("ProgramFiles");
                String pf86 = System.getenv("ProgramFiles(x86)");
                String lad  = System.getenv("LOCALAPPDATA");
                found = newestRscriptUnder(new String[]{
                        pf   == null ? null : pf   + "\\R",
                        pf86 == null ? null : pf86 + "\\R",
                        lad  == null ? null : lad  + "\\Programs\\R",
                        "C:\\R",
                });
            }
            // 4. Windows registry (HKLM / HKCU, incl. 32-bit view)
            if (found == null) {
                found = registryRscript();
            }
        } catch (Exception ignored) {}
        cachedRscriptPath = found;
        rscriptResolved = true;
        return found;
    }

    private static String whereRscript() {
        try {
            ProcessBuilder pb = new ProcessBuilder("where.exe", "Rscript.exe");
            pb.redirectErrorStream(true);
            Process p = pb.start();
            String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            boolean ok = p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
            if (!ok) { p.destroyForcibly(); return null; }
            if (p.exitValue() != 0) return null;
            for (String line : out.split("\\r?\\n")) {
                String s = line.trim();
                if (!s.isEmpty() && new File(s).isFile()) return s;
            }
        } catch (Exception ignored) {}
        return null;
    }

    private static String firstExisting(String... paths) {
        if (paths == null) return null;
        for (String p : paths) {
            if (p != null && new File(p).isFile()) return p;
        }
        return null;
    }

    /** Search "&lt;root&gt;\R-x.y.z\bin[\x64|\i386]\Rscript.exe" and return the newest. */
    private static String newestRscriptUnder(String[] roots) {
        File best = null;
        String bestVer = null;
        if (roots == null) return null;
        for (String root : roots) {
            if (root == null) continue;
            File[] versions = new File(root).listFiles(
                    f -> f.isDirectory() && f.getName().startsWith("R-"));
            if (versions == null) continue;
            for (File v : versions) {
                String[] subs = {"bin\\x64\\Rscript.exe", "bin\\Rscript.exe", "bin\\i386\\Rscript.exe"};
                for (String sub : subs) {
                    File exe = new File(v, sub);
                    if (exe.isFile()) {
                        String ver = v.getName().substring(2); // strip "R-"
                        if (bestVer == null || compareVersions(ver, bestVer) > 0) {
                            bestVer = ver; best = exe;
                        }
                        break;
                    }
                }
            }
        }
        return best != null ? best.getAbsolutePath() : null;
    }

    private static int compareVersions(String a, String b) {
        String[] pa = a.split("[.\\-]"), pb = b.split("[.\\-]");
        int n = Math.max(pa.length, pb.length);
        for (int i = 0; i < n; i++) {
            int x = i < pa.length ? parseIntSafe(pa[i]) : 0;
            int y = i < pb.length ? parseIntSafe(pb[i]) : 0;
            if (x != y) return Integer.compare(x, y);
        }
        return 0;
    }

    private static int parseIntSafe(String s) {
        try { return Integer.parseInt(s.trim()); } catch (Exception e) { return 0; }
    }

    /** Look up R's install path from the Windows registry. */
    private static String registryRscript() {
        String[] keys = {
                "HKLM\\SOFTWARE\\R-core\\R",
                "HKCU\\SOFTWARE\\R-core\\R",
                "HKLM\\SOFTWARE\\WOW6432Node\\R-core\\R",
        };
        for (String key : keys) {
            String installPath = regQuery(key, "InstallPath");
            String exe = firstExisting(
                    installPath == null ? null : installPath + "\\bin\\x64\\Rscript.exe",
                    installPath == null ? null : installPath + "\\bin\\Rscript.exe");
            if (exe != null) return exe;
        }
        return null;
    }

    private static String regQuery(String key, String value) {
        try {
            ProcessBuilder pb = new ProcessBuilder("reg.exe", "query", key, "/v", value);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            boolean ok = p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
            if (!ok) { p.destroyForcibly(); return null; }
            if (p.exitValue() != 0) return null;
            for (String line : out.split("\\r?\\n")) {
                int idx = line.indexOf("REG_SZ");
                if (idx >= 0) return line.substring(idx + "REG_SZ".length()).trim();
            }
        } catch (Exception ignored) {}
        return null;
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
        // Source conda AND activate the EzMAP2-qiime2 env, because R/Rscript is
        // installed into that env by install.sh (not into conda's base env).
        // Without the activate step, "command -v Rscript" inside WSL fails even
        // though R is installed.
        return "for d in \"$HOME/miniconda3\" \"$HOME/miniforge3\" \"$HOME/mambaforge\" "
                + "\"$HOME/anaconda3\" \"/opt/miniconda3\" \"/opt/conda\"; do "
                + "if [ -f \"$d/etc/profile.d/conda.sh\" ]; then "
                + "source \"$d/etc/profile.d/conda.sh\"; break; fi; done; "
                + "conda activate EzMAP2-qiime2 2>/dev/null; ";
    }

    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }
}
