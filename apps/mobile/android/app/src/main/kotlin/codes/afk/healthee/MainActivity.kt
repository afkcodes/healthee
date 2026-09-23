package codes.afk.healthee

import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestPeakRefreshRate()
    }

    /**
     * Ask for the panel's fastest refresh rate AT THE RESOLUTION IT IS ALREADY IN.
     *
     * Android can hand an app 60 Hz on a 120 Hz panel unless the window asks for
     * a mode. The `refresh_rate` plugin used to do the asking, and it chose the
     * mode by refresh rate alone: on a Pixel 8 Pro set to "High resolution"
     * (1008×2244) it picked 1344×2992@120, so the panel changed resolution on
     * every open and changed back on every close. That is the flash / garbled
     * frame seen on launch and resume. Filtering by the current physical size
     * means the request never causes a resolution switch.
     */
    private fun requestPeakRefreshRate() {
        val display: Display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display ?: return
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
        val current = display.mode
        val peak = display.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxByOrNull { it.refreshRate } ?: return
        window.attributes = window.attributes.also { it.preferredDisplayModeId = peak.modeId }
    }
}
