package EzMAP2.ui;

import javax.swing.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * Cross-platform QIIME2 command executor.
 *
 * Builds and runs a single QIIME2 CLI command on any OS:
 *   Windows → WSL (bash -lc "conda activate EzMAP2-qiime2; qiime …")
 *   Linux/macOS → bash -lc "conda activate EzMAP2-qiime2; qiime …"
 *
 * Usage:
 *   QiimeCommand cmd = new QiimeCommand("qiime tools import")
 *       .arg("--type", "SampleData[PairedEndSequencesWithQuality]")
 *       .arg("--input-path", manifestFile)
 *       .flag("--verbose")
 *       .workDir(outputDir);
 *   int exit = cmd.run(console);
 *
 * Pipeline-log persistence (Expert Mode):
 *   Easy Mode tees every line of its shell script to
 *     {@code <outputDir>/logs/pipeline.log}
 *   Expert Mode used to leave the log only in the in-memory LogConsole.
 *   Now, once {@link #setPipelineLogFile(File)} has been called (e.g. by
 *   ManifestPage after the user validates inputs), every subsequent
 *   {@code run()} / {@code runBash()} call also appends its branded header,
 *   each output line, and the success/failure footer to that file — so
 *   the Expert run produces the same {@code logs/pipeline.log} artifact
 *   as the Easy Mode script.
 */
public class QiimeCommand {

    private static final String ENV_NAME = "EzMAP2-qiime2";

    /**
     * Shared pipeline log file. Set once per Expert Mode run after the
     * output directory is known; null means "do not persist" (e.g.
     * environment setup, database download, classifier training — those
     * happen before any output directory exists).
     */
    private static volatile File pipelineLogFile;
    private static final SimpleDateFormat LOG_TS_FMT =
            new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

    /**
     * Configure the pipeline log file. Pass null to disable file logging.
     * Parent directories are created on demand. Safe to call repeatedly;
     * later calls replace the previous target.
     */
    public static void setPipelineLogFile(File f) {
        pipelineLogFile = f;
        if (f != null) {
            File parent = f.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
        }
    }

    /** Current log file (null if not configured). */
    public static File getPipelineLogFile() { return pipelineLogFile; }

    /**
     * Append a single line to the pipeline log file with a timestamp +
     * level prefix. Thread-safe. Silently ignores write errors so a
     * disk problem never breaks the running pipeline.
     */
    private static void writeLogLine(String level, String line) {
        File f = pipelineLogFile;
        if (f == null) return;
        try {
            String ts = LOG_TS_FMT.format(new Date());
            String prefixed = "[" + ts + "] " + (level == null ? "" : "[" + level + "] ")
                    + (line == null ? "" : line) + System.lineSeparator();
            Files.write(f.toPath(), prefixed.getBytes(StandardCharsets.UTF_8),
                    StandardOpenOption.CREATE,
                    StandardOpenOption.WRITE,
                    StandardOpenOption.APPEND);
        } catch (IOException ignore) {
            // Disk failure must not break the pipeline.
        }
    }

    private final StringBuilder command = new StringBuilder();
    private File workDir;
    private volatile Process process;

    /** Start building a command, e.g. "qiime tools import" */
    public QiimeCommand(String base) {
        command.append(base);
    }

    /** Append --name value */
    public QiimeCommand arg(String name, String value) {
        if (value != null && !value.isEmpty()) {
            command.append(" ").append(name).append(" ").append(q(value));
        }
        return this;
    }

    /** Append --name value (numeric) */
    public QiimeCommand arg(String name, int value) {
        command.append(" ").append(name).append(" ").append(value);
        return this;
    }

    /** Append --name value (double) */
    public QiimeCommand arg(String name, double value) {
        command.append(" ").append(name).append(" ").append(value);
        return this;
    }

    /** Append a flag with no value, e.g. --verbose */
    public QiimeCommand flag(String name) {
        command.append(" ").append(name);
        return this;
    }

    /** Append raw text to the command */
    public QiimeCommand raw(String text) {
        command.append(" ").append(text);
        return this;
    }

    /** Set working directory */
    public QiimeCommand workDir(File dir) {
        this.workDir = dir;
        return this;
    }

    /** Set working directory */
    public QiimeCommand workDir(String dir) {
        if (dir != null && !dir.isEmpty()) {
            this.workDir = new File(dir);
        }
        return this;
    }

    /** Get the running process (for cancellation) */
    public Process getProcess() { return process; }

    /** Stop the running process */
    public void cancel() {
        if (process != null && process.isAlive()) {
            process.destroy();
        }
    }

    /**
     * Execute the command, streaming output to the LogConsole.
     * Blocks until completion. Returns exit code (0 = success).
     */
    public int run(LogConsole console) throws IOException, InterruptedException {
        return run(console, null);
    }

    /**
     * Execute the command, streaming output to the LogConsole.
     * The optional lineCallback receives each output line (on the EDT).
     *
     * Logs a branded header, the full QIIME2 command, timing, and result.
     */
    public int run(LogConsole console, Consumer<String> lineCallback)
            throws IOException, InterruptedException {

        String osName = System.getProperty("os.name").toLowerCase();
        boolean isWindows = osName.contains("win");

        // Build the full command with conda activation
        String qiimeCmd = command.toString();

        // On Windows, convert any Windows paths in the command to WSL paths
        if (isWindows) {
            qiimeCmd = convertPathsToWsl(qiimeCmd);
        }

        String fullCmd = condaActivate() + qiimeCmd;

        // ---- Branded header ----
        final String displayCmd = command.toString();
        final String timestamp = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss")
                .format(new java.util.Date());
        SwingUtilities.invokeLater(() -> {
            console.info("================================================================");
            console.info("  EzMAP v2 \u2014 Expert Mode");
            console.info("  " + timestamp);
            console.info("================================================================");
            console.info("");
            console.info("Command:");
            console.info("  $ " + displayCmd);
            console.info("");
            if (workDir != null) {
                console.info("Working directory: " + workDir.getAbsolutePath());
            }
            console.info("Executing... this may take a while.");
            console.info("----------------------------------------------------------------");
        });

        // Mirror the same header to the pipeline.log file, if configured,
        // so Expert Mode produces the same artifact as easy_mode.sh.
        writeLogLine("INFO", "================================================================");
        writeLogLine("INFO", "  EzMAP v2 \u2014 Expert Mode");
        writeLogLine("INFO", "  " + timestamp);
        writeLogLine("INFO", "================================================================");
        writeLogLine("INFO", "Command:");
        writeLogLine("INFO", "  $ " + displayCmd);
        if (workDir != null) {
            writeLogLine("INFO", "Working directory: " + workDir.getAbsolutePath());
        }
        writeLogLine("INFO", "Executing...");
        writeLogLine("INFO", "----------------------------------------------------------------");

        long startTime = System.currentTimeMillis();

        ProcessBuilder pb;
        if (isWindows) {
            pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--",
                    "bash", "-lc", fullCmd);
        } else {
            pb = new ProcessBuilder("bash", "-lc", fullCmd);
        }

        pb.redirectErrorStream(true);
        if (workDir != null && workDir.isDirectory()) {
            pb.directory(workDir);
        }

        process = pb.start();

        try (BufferedReader r = new BufferedReader(
                new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                final String s = line;
                final String level;
                if (s.contains("Error") || s.contains("error") || s.contains("FAILED")) {
                    level = "ERROR";
                } else if (s.contains("Warning") || s.contains("warning")) {
                    level = "WARN";
                } else {
                    level = "INFO";
                }
                // Tee to the on-disk pipeline log (if configured)
                writeLogLine(level, s);
                SwingUtilities.invokeLater(() -> {
                    if ("ERROR".equals(level))      console.err(s);
                    else if ("WARN".equals(level))  console.warn(s);
                    else                            console.info(s);
                    if (lineCallback != null) lineCallback.accept(s);
                });
            }
        }

        int exit = process.waitFor();
        long elapsed = System.currentTimeMillis() - startTime;
        final int exitCode = exit;
        final String duration = formatDuration(elapsed);

        SwingUtilities.invokeLater(() -> {
            console.info("----------------------------------------------------------------");
            if (exitCode == 0) {
                console.ok("\u2713 Command completed successfully.");
            } else {
                console.err("\u2718 Command failed (exit code " + exitCode + ").");
            }
            console.info("Elapsed time: " + duration);
            console.info("================================================================");
        });

        // Footer in the on-disk log
        writeLogLine("INFO", "----------------------------------------------------------------");
        writeLogLine(exitCode == 0 ? "OK" : "ERROR",
                exitCode == 0
                        ? "Command completed successfully."
                        : "Command failed (exit code " + exitCode + ").");
        writeLogLine("INFO", "Elapsed time: " + duration);
        writeLogLine("INFO", "================================================================");
        writeLogLine("INFO", "");

        return exit;
    }

    // ==================================================================
    //  Static helpers — also useful for non-QIIME commands
    // ==================================================================

    /**
     * Run a raw bash command with conda activation and stream to console.
     * Useful for biom, sed, cp, etc. that need the conda env for biom tools.
     */
    public static int runBash(String bashCmd, File workDir, LogConsole console)
            throws IOException, InterruptedException {
        String osName = System.getProperty("os.name").toLowerCase();
        boolean isWindows = osName.contains("win");

        SwingUtilities.invokeLater(() -> console.info("$ " + bashCmd));
        writeLogLine("INFO", "$ " + bashCmd);
        if (workDir != null) writeLogLine("INFO", "  (cwd: " + workDir.getAbsolutePath() + ")");

        // Activate conda so tools like 'biom' are available
        String fullCmd = condaActivate() + bashCmd;

        ProcessBuilder pb;
        if (isWindows) {
            fullCmd = convertPathsToWsl(fullCmd);
            pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--",
                    "bash", "-lc", fullCmd);
        } else {
            pb = new ProcessBuilder("bash", "-lc", fullCmd);
        }
        pb.redirectErrorStream(true);
        if (workDir != null) pb.directory(workDir);

        Process proc = pb.start();
        try (BufferedReader r = new BufferedReader(
                new InputStreamReader(proc.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                final String s = line;
                writeLogLine("INFO", s);
                SwingUtilities.invokeLater(() -> console.info(s));
            }
        }
        int exit = proc.waitFor();
        writeLogLine(exit == 0 ? "OK" : "ERROR",
                exit == 0
                        ? "(bash command completed)"
                        : "(bash command failed, exit code " + exit + ")");
        return exit;
    }

    // ==================================================================
    //  Internal helpers
    // ==================================================================

    /**
     * Conda activation preamble — directly sources conda.sh then activates env.
     *
     * .bashrc won't work because it has a non-interactive guard that exits early.
     * Instead, we directly source conda.sh from known install locations
     * (same approach as easy_mode.sh which works reliably).
     */
    private static String condaActivate() {
        // Chain direct source attempts — exactly what easy_mode.sh does
        return "source \"$HOME/miniconda3/etc/profile.d/conda.sh\" 2>/dev/null || "
                + "source \"$HOME/miniforge3/etc/profile.d/conda.sh\" 2>/dev/null || "
                + "source \"$HOME/mambaforge/etc/profile.d/conda.sh\" 2>/dev/null || "
                + "source \"$HOME/anaconda3/etc/profile.d/conda.sh\" 2>/dev/null || "
                + "source \"/opt/conda/etc/profile.d/conda.sh\" 2>/dev/null || "
                + "{ echo 'ERROR: conda not found. Install miniconda3 or run install.sh first.'; exit 1; }; "
                + "conda activate " + ENV_NAME + " || "
                + "{ echo 'ERROR: Failed to activate conda env " + ENV_NAME
                + ". Run install.sh first.'; exit 1; }; ";
    }

    /** Shell-quote a value. */
    private static String q(String val) {
        if (val == null || val.isEmpty()) return "\"\"";
        // If already quoted, return as-is
        if (val.startsWith("\"") && val.endsWith("\"")) return val;
        return "\"" + val.replace("\"", "\\\"") + "\"";
    }

    /**
     * Convert Windows-style paths (C:\...) to WSL paths (/mnt/c/...)
     * in a command string. Only converts paths that look like drive letters.
     */
    static String convertPathsToWsl(String cmd) {
        // Pattern: quoted or unquoted Windows paths like C:\Users\... or "C:\Users\..."
        // Replace backslashes first
        String result = cmd.replace("\\", "/");
        // Convert drive letters: C:/ → /mnt/c/
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < result.length(); i++) {
            if (i + 2 < result.length()
                    && Character.isLetter(result.charAt(i))
                    && result.charAt(i + 1) == ':'
                    && result.charAt(i + 2) == '/'
                    && (i == 0 || result.charAt(i - 1) == '"' || result.charAt(i - 1) == ' '
                        || result.charAt(i - 1) == '=')) {
                sb.append("/mnt/").append(Character.toLowerCase(result.charAt(i)));
                i++; // skip the ':'
            } else {
                sb.append(result.charAt(i));
            }
        }
        return sb.toString();
    }

    /** Convert a single Windows path to WSL format. */
    public static String toWsl(String winPath) {
        if (winPath == null || winPath.isEmpty()) return winPath;
        String p = winPath.replace("\\", "/");
        if (p.length() >= 2 && p.charAt(1) == ':') {
            return "/mnt/" + Character.toLowerCase(p.charAt(0)) + p.substring(2);
        }
        return p;
    }

    /** Format milliseconds into a human-readable duration string. */
    private static String formatDuration(long millis) {
        if (millis < 1000) return millis + "ms";
        long secs = TimeUnit.MILLISECONDS.toSeconds(millis);
        long mins = TimeUnit.MILLISECONDS.toMinutes(millis);
        long hrs  = TimeUnit.MILLISECONDS.toHours(millis);
        if (hrs > 0) {
            return String.format("%dh %dm %ds", hrs, mins % 60, secs % 60);
        } else if (mins > 0) {
            return String.format("%dm %ds", mins, secs % 60);
        } else {
            return secs + "s";
        }
    }

    /**
     * Get the built command string (for display in preview cards).
     */
    public String getCommandString() {
        return command.toString();
    }
}
