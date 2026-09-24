package nl.g4d.homemaps.car

import android.content.Intent
import android.content.res.Configuration
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.ScreenManager
import androidx.car.app.Session
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import nl.g4d.homemaps.car.screens.HomeScreen
import nl.g4d.homemaps.car.screens.NavigationScreen
import nl.g4d.homemaps.car.screens.RoutePreviewScreen

/**
 * One connection to a car's main display. Starts the Flutter engine if the
 * phone's app isn't running, draws the map on the car's surface and keeps
 * the screen stack in step with what Dart shows.
 */
class HomemapsSession : Session(), CarHost.Listener {
    private lateinit var renderer: MapSurfaceRenderer
    private var lastScreen: CarHost.Screen? = null

    override fun onCreateScreen(intent: Intent): Screen {
        FlutterEngineHolder.get(carContext)
        renderer = MapSurfaceRenderer(carContext, "main")
        renderer.attach()
        CarHost.addListener(this)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CarHost.removeListener(this@HomemapsSession)
                renderer.detach()
                CarHost.surfaceGone()
                CarNotification.clear(carContext)
            }
        })
        val navigation = carContext.getCarService(NavigationManager::class.java)
        navigation.setNavigationManagerCallback(object : NavigationManagerCallback {
            override fun onStopNavigation() = CarHost.stopTrip()
            override fun onAutoDriveEnabled() = CarHost.autoDriveEnabled()
        })
        handleIntent(intent)
        lastScreen = CarHost.screen
        return when (CarHost.screen) {
            CarHost.Screen.NAVIGATING, CarHost.Screen.ARRIVED -> NavigationScreen(carContext)
            CarHost.Screen.PREVIEW -> RoutePreviewScreen(carContext)
            CarHost.Screen.HOME -> HomeScreen(carContext)
        }
    }

    override fun onNewIntent(intent: Intent) = handleIntent(intent)

    /** A `geo:` link or "navigate to" from the car (the assistant, for one). */
    private fun handleIntent(intent: Intent) {
        if (intent.action != CarContext.ACTION_NAVIGATE) return
        val uri = intent.data ?: return
        val request = GeoLink.parse(uri) ?: return
        CarHost.navigateTo(request.lat, request.lon, request.label, request.query)
    }

    override fun onCarConfigurationChanged(newConfiguration: Configuration) {
        renderer.darkModeChanged()
    }

    // ---------------------------------------------------------------- Dart

    /**
     * Dart moved to another screen: the stack follows. Home is the root;
     * preview and navigation sit on top of it.
     */
    override fun onScreen() {
        val screen = CarHost.screen
        if (screen == lastScreen) return
        lastScreen = screen
        val manager = carContext.getCarService(ScreenManager::class.java)
        when (screen) {
            CarHost.Screen.HOME -> {
                manager.popToRoot()
                CarNotification.clear(carContext)
            }
            CarHost.Screen.PREVIEW -> {
                manager.popToRoot()
                manager.push(RoutePreviewScreen(carContext))
            }
            CarHost.Screen.NAVIGATING -> {
                manager.popToRoot()
                manager.push(NavigationScreen(carContext))
                carContext.getCarService(NavigationManager::class.java).navigationStarted()
            }
            CarHost.Screen.ARRIVED -> {
                carContext.getCarService(NavigationManager::class.java).navigationEnded()
            }
        }
    }
}
