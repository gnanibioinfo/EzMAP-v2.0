package EzMAP2;

import EzMAP2.ui.Theme;

import javax.swing.*;

/** Application entry point. Installs FlatLaf + the EzMAP theme, then shows the main frame. */
public class Main {

    public static void main(String[] args) {
        try {
            // Try FlatLaf if on classpath (preferred modern look).
            // Falls back to Nimbus, then the system L&F.
            try {
                Class<?> flat = Class.forName("com.formdev.flatlaf.FlatLightLaf");
                flat.getMethod("setup").invoke(null);
            } catch (ClassNotFoundException cnf) {
                for (UIManager.LookAndFeelInfo info : UIManager.getInstalledLookAndFeels()) {
                    if ("Nimbus".equals(info.getName())) {
                        UIManager.setLookAndFeel(info.getClassName());
                        break;
                    }
                }
            }
        } catch (Exception ex) {
            ex.printStackTrace();
        }

        Theme.install();
        SwingUtilities.invokeLater(() -> new MainFrame().setVisible(true));
    }
}
