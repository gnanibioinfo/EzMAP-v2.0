package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;

/** Teal outlined button — secondary action. */
public class OutlineButton extends JButton {

    public OutlineButton(String text) {
        super(text);
        setFont(Theme.FONT_BUTTON);
        setForeground(Theme.PRIMARY_DARK);
        setBackground(Theme.SURFACE);
        setFocusPainted(false);
        setOpaque(true);
        setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.PRIMARY, 1, true),
                BorderFactory.createEmptyBorder(
                        Theme.PAD_BUTTON.top - 1, Theme.PAD_BUTTON.left - 1,
                        Theme.PAD_BUTTON.bottom - 1, Theme.PAD_BUTTON.right - 1)));
        setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));

        addMouseListener(new MouseAdapter() {
            @Override public void mouseEntered(MouseEvent e) {
                if (isEnabled()) setBackground(Theme.PRIMARY_SOFT);
            }
            @Override public void mouseExited(MouseEvent e) {
                setBackground(Theme.SURFACE);
            }
        });
    }
}
