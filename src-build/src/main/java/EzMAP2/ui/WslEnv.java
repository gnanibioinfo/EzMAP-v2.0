package EzMAP2.ui;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

/**
 * Central resolver for the installed WSL Ubuntu distribution name.
 *
 * <p>Different machines name their Ubuntu distro differently — a fresh
 * {@code wsl --install} produces <b>"Ubuntu"</b>, while the Microsoft Store
 * "Ubuntu 24.04 LTS" registers as <b>"Ubuntu-24.04"</b>. Hardcoding
 * {@code wsl -d Ubuntu} fails on the latter with:
 * <pre>There is no distribution with the supplied name "Ubuntu".</pre>
 *
 * <p>Every place that launches a process via {@code wsl.exe -d &lt;distro&gt;}
 * must use {@link #distro()} instead of a literal so the app works on any
 * Ubuntu-* installation. The result is resolved once and cached.
 */
public final class WslEnv {

    private static volatile String cached;

    private WslEnv() { }

    /**
     * The real Ubuntu distribution name to pass to {@code wsl -d ...}
     * (e.g. "Ubuntu" or "Ubuntu-24.04"). Resolved from {@code wsl -l -q}
     * on first use and cached. Falls back to "Ubuntu" if detection fails.
     */
    public static String distro() {
        String c = cached;
        if (c != null) return c;
        synchronized (WslEnv.class) {
            if (cached == null) cached = resolve();
            return cached;
        }
    }

    /** Seed the cache with a name already resolved elsewhere (e.g. setup page). */
    public static void setDistro(String name) {
        if (name != null && !name.trim().isEmpty()) {
            cached = name.trim();
        }
    }

    /** Clear the cache so the next {@link #distro()} re-detects (e.g. after install). */
    public static void refresh() {
        cached = null;
    }

    private static String resolve() {
        try {
            ProcessBuilder pb = new ProcessBuilder("wsl.exe", "-l", "-q");
            pb.redirectErrorStream(true);
            Process p = pb.start();
            byte[] raw = p.getInputStream().readAllBytes();
            p.waitFor();
            String asUtf8 = new String(raw, StandardCharsets.UTF_8);
            // `wsl.exe` emits UTF-16LE on many systems; detect via embedded NUL.
            String out = asUtf8.indexOf('\0') >= 0
                    ? new String(raw, Charset.forName("UTF-16LE"))
                    : asUtf8;
            String name = parseUbuntu(out);
            if (name != null) return name;
        } catch (Exception ignored) {
            // fall through to default
        }
        return "Ubuntu";
    }

    /**
     * Pick the Ubuntu distro name from {@code wsl -l -q} output. Handles WSL's
     * quirky encoding (UTF-16LE, stray NUL bytes, BOM) and multiple installed
     * distros. Prefers an exact "Ubuntu", otherwise the first name containing
     * "ubuntu" (e.g. "Ubuntu-24.04"). Returns null if none found.
     */
    public static String parseUbuntu(String rawOutput) {
        if (rawOutput == null) return null;
        String cleaned = rawOutput.replaceAll("[\\u0000\\uFEFF]", "");
        String firstMatch = null;
        for (String raw : cleaned.split("\\r?\\n")) {
            String name = raw.trim();
            if (name.isEmpty()) continue;
            // `wsl -l` (non-quiet) may append " (Default)" to the default distro.
            int paren = name.indexOf(" (");
            if (paren > 0) name = name.substring(0, paren).trim();
            if (name.equalsIgnoreCase("Ubuntu")) return name;       // exact preferred
            if (name.toLowerCase().contains("ubuntu") && firstMatch == null) {
                firstMatch = name;
            }
        }
        return firstMatch;
    }
}
