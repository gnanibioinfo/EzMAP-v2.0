package EzMAP2;

import EzMAP2.pages.BasePage;

import javax.swing.*;
import java.awt.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.HashMap;

/**
 * Owns the registered pages plus the currently active flow (an ordered
 * subset of page IDs). Easy Mode and Expert Mode swap the active flow,
 * which drives the sidebar labels, footer progress and Back/Next nav.
 *
 * Also provides a shared key-value store ({@link #put}/{@link #get})
 * for passing data between pages (e.g. output file paths from one step
 * to the next in Expert Mode).
 */
public class WizardController {

    private final JPanel cards;
    private final CardLayout layout;
    private final LinkedHashMap<String, BasePage> pages = new LinkedHashMap<>();

    /** Shared key-value store for inter-page communication. */
    private final HashMap<String, String> properties = new HashMap<>();

    /** Ordered list of page IDs currently shown in sidebar/footer. */
    private List<String> activeFlow = new ArrayList<>();
    /** Matching human-readable labels used by the sidebar StepList. */
    private List<String> activeLabels = new ArrayList<>();

    private int currentIndex = 0;
    private Runnable onChange;
    private Runnable onFlowChange;

    public WizardController(JPanel cards, CardLayout layout) {
        this.cards = cards;
        this.layout = layout;
    }

    public void addPage(String id, BasePage page) {
        pages.put(id, page);
        cards.add(page, id);
    }

    public void setOnChange(Runnable r)     { this.onChange = r; }
    public void setOnFlowChange(Runnable r) { this.onFlowChange = r; }

    /** Update the ordered flow. Labels must match flow length. */
    public void setActiveFlow(List<String> ids, List<String> labels) {
        this.activeFlow   = new ArrayList<>(ids);
        this.activeLabels = new ArrayList<>(labels);
        if (currentIndex >= activeFlow.size()) currentIndex = activeFlow.size() - 1;
        if (onFlowChange != null) onFlowChange.run();
        showIndex(currentIndex);
    }

    public List<String> getActiveFlow()   { return activeFlow; }
    public List<String> getActiveLabels() { return activeLabels; }

    public void showIndex(int index) {
        if (activeFlow.isEmpty()) return;
        if (index < 0 || index >= activeFlow.size()) return;
        currentIndex = index;
        String id = activeFlow.get(index);
        layout.show(cards, id);
        BasePage page = pages.get(id);
        if (page != null) page.onShown();
        if (onChange != null) onChange.run();
    }

    /** Jump to a page by its registered ID (must be in the active flow). */
    public void showId(String id) {
        int i = activeFlow.indexOf(id);
        if (i >= 0) showIndex(i);
    }

    public void next()     { showIndex(Math.min(currentIndex + 1, activeFlow.size() - 1)); }
    public void previous() { showIndex(Math.max(currentIndex - 1, 0)); }

    public int    getCurrentIndex() { return currentIndex; }
    public int    getTotal()        { return activeFlow.size(); }
    public String getCurrentId()    { return activeFlow.isEmpty() ? null : activeFlow.get(currentIndex); }
    public Map<String, BasePage> getPages() { return pages; }

    // ==================================================================
    //  Shared properties (inter-page communication for Expert Mode)
    // ==================================================================

    /** Store a value accessible by any page. */
    public void put(String key, String value) { properties.put(key, value); }

    /** Retrieve a stored value (null if not set). */
    public String get(String key) { return properties.get(key); }

    /** Retrieve a stored value with a default fallback. */
    public String get(String key, String defaultValue) {
        return properties.getOrDefault(key, defaultValue);
    }

    /** Clear all stored properties (e.g. when switching flows). */
    public void clearProperties() { properties.clear(); }
}
