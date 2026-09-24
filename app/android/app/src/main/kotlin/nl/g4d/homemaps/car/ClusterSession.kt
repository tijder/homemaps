package nl.g4d.homemaps.car

import android.content.Intent
import android.content.res.Configuration
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import nl.g4d.homemaps.car.screens.NavigationScreen

/** The instrument cluster: the same map and the next turn, nothing to press. */
class ClusterSession : Session() {
    private lateinit var renderer: MapSurfaceRenderer

    override fun onCreateScreen(intent: Intent): Screen {
        FlutterEngineHolder.get(carContext)
        renderer = MapSurfaceRenderer(carContext, "cluster")
        renderer.attach()
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) = renderer.detach()
        })
        return NavigationScreen(carContext, cluster = true)
    }

    override fun onCarConfigurationChanged(newConfiguration: Configuration) {
        renderer.darkModeChanged()
    }
}
