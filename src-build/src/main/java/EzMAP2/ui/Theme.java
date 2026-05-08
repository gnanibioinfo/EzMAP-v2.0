package EzMAP2.ui;

import javax.swing.BorderFactory;
import javax.swing.UIManager;
import javax.swing.border.Border;
import java.awt.Color;
import java.awt.Font;
import java.awt.Insets;

/**
 * Single source of truth for all visual constants in EzMAP2.
 * Change a value here and every page, button, and card updates.
 */
public final class Theme {

    private Theme() {}

    // ---- Palette -----------------------------------------------------------
    public static final Color PRIMARY         = new Color(0x0E, 0xA5, 0xA4); // teal-500
    public static final Color PRIMARY_DARK    = new Color(0x0B, 0x8F, 0x8E); // teal-600
    public static final Color PRIMARY_SOFT    = new Color(0xE6, 0xFF, 0xFB);
    public static final Color PRIMARY_BORDER  = new Color(0xA7, 0xF3, 0xF1);

    public static final Color ACCENT          = new Color(0x4F, 0x46, 0xE5); // indigo-600

    public static final Color INK_1           = new Color(0x0F, 0x17, 0x2A); // slate-900
    public static final Color INK_2           = new Color(0x33, 0x41, 0x55); // slate-700
    public static final Color INK_3           = new Color(0x64, 0x74, 0x8B); // slate-500

    public static final Color SURFACE         = Color.WHITE;
    public static final Color SURFACE_2       = new Color(0xF8, 0xFA, 0xFC);
    public static final Color BACKGROUND      = new Color(0xF4, 0xF6, 0xF8);
    public static final Color BORDER          = new Color(0xE2, 0xE8, 0xF0);

    public static final Color SIDEBAR_TOP     = new Color(0x0F, 0x76, 0x6E);
    public static final Color SIDEBAR_BOTTOM  = new Color(0x0B, 0x5E, 0x5D);

    public static final Color SUCCESS         = new Color(0x16, 0xA3, 0x4A);
    public static final Color WARNING         = new Color(0xD9, 0x77, 0x06);
    public static final Color DANGER          = new Color(0xDC, 0x26, 0x26);

    public static final Color CONSOLE_BG      = new Color(0x0B, 0x12, 0x20);
    public static final Color CONSOLE_FG      = new Color(0xD1, 0xFA, 0xE5);
    public static final Color CONSOLE_OK      = new Color(0x86, 0xEF, 0xAC);
    public static final Color CONSOLE_WARN    = new Color(0xFD, 0xE6, 0x8A);
    public static final Color CONSOLE_ERR     = new Color(0xFC, 0xA5, 0xA5);

    // ---- Typography --------------------------------------------------------
    private static final String SANS = pickFont("Inter", "Segoe UI", "SansSerif");
    private static final String MONO = pickFont("JetBrains Mono", "Consolas", "Monospaced");

    public static final Font FONT_PAGE_TITLE  = new Font(SANS, Font.BOLD,  24);
    public static final Font FONT_SECTION     = new Font(SANS, Font.BOLD,  15);
    public static final Font FONT_BODY        = new Font(SANS, Font.PLAIN, 14);
    public static final Font FONT_BODY_BOLD   = new Font(SANS, Font.BOLD,  14);
    public static final Font FONT_SMALL       = new Font(SANS, Font.PLAIN, 12);
    public static final Font FONT_LABEL       = new Font(SANS, Font.BOLD,  11);
    public static final Font FONT_MONO        = new Font(MONO, Font.PLAIN, 12);
    public static final Font FONT_BUTTON      = new Font(SANS, Font.BOLD,  13);
    public static final Font FONT_BRAND       = new Font(SANS, Font.BOLD,  15);
    public static final Font FONT_BRAND_SUB   = new Font(SANS, Font.PLAIN, 11);

    // ---- Spacing / radius --------------------------------------------------
    public static final int  RADIUS           = 10;
    public static final int  RADIUS_SMALL     = 8;
    public static final Insets PAD_BUTTON     = new Insets(9, 16, 9, 16);
    public static final Insets PAD_CARD       = new Insets(18, 20, 18, 20);
    public static final Insets PAD_PAGE       = new Insets(24, 32, 24, 32);

    public static Border emptyBorder(int t, int l, int b, int r) {
        return BorderFactory.createEmptyBorder(t, l, b, r);
    }

    public static Border cardBorder() {
        return BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(BORDER, 1, true),
                BorderFactory.createEmptyBorder(PAD_CARD.top, PAD_CARD.left,
                                                PAD_CARD.bottom, PAD_CARD.right));
    }

    /** Apply FlatLaf UIManager overrides so standard Swing widgets pick up the theme. */
    public static void install() {
        UIManager.put("Component.focusWidth", 1);
        UIManager.put("Component.innerFocusWidth", 0);
        UIManager.put("Component.arc",              RADIUS_SMALL);
        UIManager.put("Button.arc",                 RADIUS_SMALL);
        UIManager.put("TextComponent.arc",          RADIUS_SMALL);
        UIManager.put("ScrollBar.thumbArc",         999);
        UIManager.put("ScrollBar.thumbInsets",      new Insets(2, 2, 2, 2));

        UIManager.put("Panel.background",           BACKGROUND);
        UIManager.put("TextField.background",       SURFACE);
        UIManager.put("TextField.foreground",       INK_1);
        UIManager.put("TextField.borderColor",      BORDER);
        UIManager.put("TextField.focusedBorderColor", PRIMARY);

        UIManager.put("Button.background",          SURFACE);
        UIManager.put("Button.foreground",          INK_2);
        UIManager.put("Button.focusedBorderColor",  PRIMARY);

        UIManager.put("defaultFont",                FONT_BODY);
        UIManager.put("Label.font",                 FONT_BODY);
        UIManager.put("Label.foreground",           INK_2);
    }

    // ---- helpers -----------------------------------------------------------
    private static String pickFont(String... candidates) {
        java.util.Set<String> available = new java.util.HashSet<>();
        for (String name : java.awt.GraphicsEnvironment
                .getLocalGraphicsEnvironment()
                .getAvailableFontFamilyNames()) {
            available.add(name);
        }
        for (String c : candidates) {
            if (available.contains(c)) return c;
        }
        return candidates[candidates.length - 1];
    }
}
