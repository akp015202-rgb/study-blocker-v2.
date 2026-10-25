package com.studyblocker.study_blocker

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.SharedPreferences
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.inputmethod.InputMethodManager

/**
 * Chowkidaar. Session chalte time:
 *  - Allowed list ke bahar ka koi bhi app khule -> HOME
 *  - YouTube: Shorts -> BACK, study channel ke bahar ki video -> BACK
 *  - YouTube tab tak band jab tak koi study channel add na ho
 */
class GuardService : AccessibilityService() {

    companion object {
        private const val YT = "com.google.android.youtube"

        // YouTube ke view ids (update me badal sakte hain)
        private val SHORTS_IDS = listOf("reel_recycler", "reel_player_page_container")
        private val WATCH_IDS = listOf("watch_player", "watch_while")

        // Hamesha allowed: system UI, calls
        private val ALWAYS_OK = setOf(
            "com.android.systemui", "android",
            "com.android.incallui", "com.android.server.telecom",
            "com.android.phone", "com.google.android.dialer",
            "com.android.dialer", "com.samsung.android.incallui"
        )
    }

    private var lastAction = 0L
    private var lastScan = 0L
    private var lastDebug = 0L
    private var watchSince = 0L
    private var sysOk: Set<String> = emptySet()
    private var sysBuilt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkg = event.packageName?.toString() ?: return
        val now = System.currentTimeMillis()
        val prefs = getSharedPreferences("guard", MODE_PRIVATE)

        // Session chal raha hai?
        if (now > prefs.getLong("session_end", 0L)) return

        if (pkg != YT) {
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                !isAllowed(pkg, prefs, now)
            ) {
                act(now, GLOBAL_ACTION_HOME)
            }
            return
        }

        handleYouTube(prefs, now)
    }

    private fun handleYouTube(prefs: SharedPreferences, now: Long) {
        val channels = (prefs.getString("channels", "") ?: "")
            .split("\n")
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }

        // Koi study channel nahi -> YouTube poora band
        if (channels.isEmpty()) {
            act(now, GLOBAL_ACTION_HOME)
            return
        }

        if (now - lastScan < 300) return
        lastScan = now

        val root = rootInActiveWindow ?: return
        if (root.packageName?.toString() != YT) return

        val ids = HashSet<String>()
        val texts = StringBuilder()
        scan(root, ids, texts, 0)

        // Debug ids save karo (app me dekhne ke liye)
        if (now - lastDebug > 2000) {
            lastDebug = now
            val sample = ids.filter { it.contains(":id/") }
                .map { it.substringAfter(":id/") }
                .sorted()
                .take(80)
                .joinToString("\n")
            prefs.edit().putString("debug_ids", sample).apply()
        }

        // 1) Shorts
        if (ids.any { id -> SHORTS_IDS.any { id.contains(it) } }) {
            act(now, GLOBAL_ACTION_BACK)
            return
        }

        // 2) Video: channel whitelist me hai?
        val onWatch = ids.any { id -> WATCH_IDS.any { id.contains(it) } }
        if (!onWatch) {
            watchSince = 0L
            return
        }

        val screenText = texts.toString().lowercase()
        if (channels.any { screenText.contains(it) }) {
            watchSince = 0L
            return
        }

        // Channel ka naam load hone ke liye 2.5 sec grace
        if (watchSince == 0L) {
            watchSince = now
        } else if (now - watchSince > 2500) {
            watchSince = 0L
            act(now, GLOBAL_ACTION_BACK)
        }
    }

    private fun isAllowed(pkg: String, prefs: SharedPreferences, now: Long): Boolean {
        if (now - sysBuilt > 60_000) {
            sysOk = buildSystemAllowed()
            sysBuilt = now
        }
        if (pkg in sysOk) return true
        val user = (prefs.getString("allowed", "") ?: "").split("\n")
        return pkg in user
    }

    private fun buildSystemAllowed(): Set<String> {
        val s = HashSet<String>(ALWAYS_OK)
        s.add(packageName)
        val pm = packageManager
        try {
            // Home screen (launcher)
            pm.queryIntentActivities(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0
            ).forEach { s.add(it.activityInfo.packageName) }
            // Dialer
            pm.queryIntentActivities(Intent(Intent.ACTION_DIAL), 0)
                .forEach { s.add(it.activityInfo.packageName) }
            // Keyboards
            val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            imm.enabledInputMethodList.forEach { s.add(it.packageName) }
        } catch (_: Exception) {
        }
        return s
    }

    private fun act(now: Long, action: Int) {
        if (now - lastAction < 800) return
        lastAction = now
        performGlobalAction(action)
    }

    private fun scan(
        node: AccessibilityNodeInfo?,
        ids: MutableSet<String>,
        texts: StringBuilder,
        depth: Int
    ) {
        if (node == null || depth > 40) return
        node.viewIdResourceName?.let { ids.add(it) }
        node.text?.let { texts.append(it).append('\n') }
        node.contentDescription?.let { texts.append(it).append('\n') }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            scan(child, ids, texts, depth + 1)
            @Suppress("DEPRECATION")
            child.recycle()
        }
    }

    override fun onInterrupt() {}
}
