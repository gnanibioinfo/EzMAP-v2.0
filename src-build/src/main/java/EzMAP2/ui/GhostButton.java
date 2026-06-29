package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;

/** Borderless neutral button — tertiary action (Back, Cancel, Help). */
public class GhostButton extends JButton {

    public GhostButton(String text) {
        super(text);
        setFont(Theme.FONT_BUTTON);
        setForeground(Theme.INK_2);
        setBackground(Theme.BACKGROUND);
        setFocusPainted(false);
        setBorderPainted(false);
        setContentAreaFilled(false);
        setOpaque(false);
        setBorder(BorderFactory.createEmptyBorder(
                Theme.PAD_BUTTON.top, Theme.PAD_BUTTON.left,
                Theme.PAD_BUTTON.bottom, Theme.PAD_BUTTON.right));
        setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));

        addMouseListener(new MouseAdapter() {
            @Override public void mouseEntered(MouseEvent e) {
                if (isEnabled()) {
                    setOpaque(true);
                    setBackground(Theme.SURFACE_2);
                    repaint();
                }
            }
            @Override public void mouseExited(MouseEvent e) {
                setOpaque(false);
                repaint();
            }
        });
    }
}
