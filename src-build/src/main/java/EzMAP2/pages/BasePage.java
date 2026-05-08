package EzMAP2.pages;

import EzMAP2.ui.Theme;

import javax.swing.*;
import java.awt.*;

/**
 * A blank content page with title + subtitle + scrollable body column.
 * All real pages extend this so the look is consistent.
 */
public abstract class BasePage extends JPanel {

    private final JPanel body;

    protected BasePage(String title, String subtitle) {
        super(new BorderLayout());
        setBackground(Theme.BACKGROUND);
        setBorder(BorderFactory.createEmptyBorder(
                Theme.PAD_PAGE.top, Theme.PAD_PAGE.left,
                Theme.PAD_PAGE.bottom, Theme.PAD_PAGE.right));

        JPanel header = new JPanel();
        header.setOpaque(false);
        header.setLayout(new BoxLayout(header, BoxLayout.Y_AXIS));
        header.setAlignmentX(LEFT_ALIGNMENT);

        JLabel t = new JLabel(title);
        t.setFont(Theme.FONT_PAGE_TITLE);
        t.setForeground(Theme.INK_1);
        t.setAlignmentX(LEFT_ALIGNMENT);
        header.add(t);

        if (subtitle != null) {
            JLabel s = new JLabel("<html>" + subtitle + "</html>");
            s.setFont(Theme.FONT_BODY);
            s.setForeground(Theme.INK_3);
            s.setAlignmentX(LEFT_ALIGNMENT);
            s.setBorder(BorderFactory.createEmptyBorder(4, 0, 16, 0));
            header.add(s);
        }
        add(header, BorderLayout.NORTH);

        body = new JPanel();
        body.setOpaque(false);
        body.setLayout(new BoxLayout(body, BoxLayout.Y_AXIS));
        body.setAlignmentX(LEFT_ALIGNMENT);

        // Both scrollbars AS_NEEDED so on small laptop screens (1366x768
        // and below) the wizard panels remain fully usable -- previously
        // HORIZONTAL_SCROLLBAR_NEVER clipped content and hid the file
        // browse / Continue buttons off-screen.
        JScrollPane scroll = new JScrollPane(body,
                JScrollPane.VERTICAL_SCROLLBAR_AS_NEEDED,
                JScrollPane.HORIZONTAL_SCROLLBAR_AS_NEEDED);
        scroll.setBorder(BorderFactory.createEmptyBorder());
        scroll.setOpaque(false);
        scroll.getViewport().setOpaque(false);
        scroll.getVerticalScrollBar().setUnitIncrement(14);
        scroll.getHorizontalScrollBar().setUnitIncrement(14);
        add(scroll, BorderLayout.CENTER);
    }

    /** Append a component to the page body column. */
    protected <T extends JComponent> T add(T c) {
        c.setAlignmentX(LEFT_ALIGNMENT);
        // Cap maximum width at a reasonable reading-line length (~960px).
        // Previously Short.MAX_VALUE made child components stretch
        // infinitely wide, which interacted badly with narrow viewports
        // on laptops -- file browse buttons drifted off the visible area
        // even with horizontal scroll enabled. Cap height as before.
        c.setMaximumSize(new Dimension(960, Short.MAX_VALUE));
        body.add(c);
        body.add(Box.createVerticalStrut(14));
        return c;
    }

    /** Access body panel for subclasses that need to scroll to bottom. */
    protected JPanel getBody() { return body; }

    /** Called by the shell when this page becomes visible. Override if needed. */
    public void onShown() {}

    /**
     * Whether this step has been completed successfully.
     * Expert pages override this to return false until their QIIME command succeeds.
     * Default returns true so non-expert pages don't block navigation.
     */
    public boolean isStepComplete() { return true; }

    /**
     * Listener that MainFrame sets so pages can notify when step completion changes.
     * Pages call this after a command succeeds/fails to update footer nav.
     */
    private Runnable stepCompletionListener;

    public void setStepCompletionListener(Runnable r) { this.stepCompletionListener = r; }

    /** Call from subclasses when step completion status changes. */
    protected void notifyStepCompletion() {
        if (stepCompletionListener != null) {
            javax.swing.SwingUtilities.invokeLater(stepCompletionListener);
        }
    }
}
