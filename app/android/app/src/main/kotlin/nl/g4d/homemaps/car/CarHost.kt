package nl.g4d.homemaps.car

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Dart's side of the car, as native sees it: everything Dart pushed, kept
 * here so a session (or a second one, the cluster) can show it whenever it
 * appears. The sessions listen for changes; Dart hears what the driver does
 * through [flutter].
 */
object CarHost : CarHostApi {
    private const val TAG = "CarHost"

    interface Listener {
        fun onStyle() {}
        fun onImage(key: String) {}
        fun onRoutes() {}
        fun onDriven() {}
        fun onArrow() {}
        fun onPosition() {}
        fun onCamera(camera: CarCamera) {}
        fun onFitBounds(bounds: CarBounds, paddingPx: Double) {}
        fun onFollowing() {}

        /** Something on the templates changed: invalidate. */
        fun onScreen() {}
        fun onAlert(alert: CarAlert?) {}
    }

    enum class Screen { HOME, PREVIEW, NAVIGATING, ARRIVED }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var flutter: CarFlutterApi? = null
    private var dartReady = false
    private val listeners = mutableSetOf<Listener>()

    /** The surface that was reported to Dart, or null while no car is there. */
    private var connectedSurface: CarSurface? = null

    var texts: Map<String, String> = emptyMap()
        private set
    var style: String? = null
        private set
    var styleIsJson = false
        private set
    val images = mutableMapOf<String, Bitmap>()
    var routesGeoJson: String? = null
        private set
    var drivenGeoJson: String? = null
        private set
    var arrowGeoJson: String? = null
        private set
    var position: CarPosition? = null
        private set
    var following = true
        private set

    var screen = Screen.HOME
        private set
    var favourites: List<CarPlace> = emptyList()
        private set
    var recents: List<CarPlace> = emptyList()
        private set
    var locationOk = false
        private set
    var homeShown = false
        private set
    var previewLabel = ""
        private set
    var previewRoutes: List<CarRouteSummary> = emptyList()
        private set
    var previewChosen = 0
        private set
    var loading = false
        private set
    var message: Pair<String, String>? = null
        private set
    var trip: CarTrip? = null
        private set
    var maneuver: CarManeuver? = null
        private set
    var speed: CarSpeed? = null
        private set
    var recalculating = false
        private set
    var arrivedAt: String? = null
        private set
    var muted = false
        private set
    var alert: CarAlert? = null
        private set

    fun text(key: String): String = texts[key] ?: key

    fun attachEngine(engine: FlutterEngine) {
        flutter = CarFlutterApi(engine.dartExecutor.binaryMessenger)
    }

    fun addListener(listener: Listener) {
        listeners.add(listener)
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    private inline fun each(block: Listener.() -> Unit) {
        for (listener in listeners.toList()) listener.block()
    }

    // --------------------------------------------------------------- to Dart

    private fun call(name: String, block: suspend CarFlutterApi.() -> Unit) {
        val api = flutter ?: return
        scope.launch {
            try {
                api.block()
            } catch (e: Exception) {
                Log.w(TAG, "$name failed: $e")
            }
        }
    }

    /** The car's screen is there (or changed). Dart hears it once it is ready. */
    fun surfaceAvailable(surface: CarSurface) {
        val first = connectedSurface == null
        connectedSurface = surface
        if (!dartReady) return
        if (first) call("connected") { connected(surface) } else call("surfaceChanged") { surfaceChanged(surface) }
    }

    fun surfaceGone() {
        connectedSurface = null
        images.clear()
        if (dartReady) call("disconnected") { disconnected() }
    }

    fun placeChosen(id: String) = call("placeChosen") { placeChosen(id) }
    fun routeChosen(index: Long) = call("routeChosen") { routeChosen(index) }
    fun startTrip() = call("startTrip") { startTrip() }
    fun stopTrip() = call("stopTrip") { stopTrip() }
    fun toggleMute() = call("toggleMute") { toggleMute() }
    fun userMovedMap() {
        following = false
        call("userMovedMap") { userMovedMap() }
    }
    fun recenter() = call("recenter") { recenter() }
    fun alertAnswered(id: String, accepted: Boolean) = call("alertAnswered") { alertAnswered(id, accepted) }
    fun autoDriveEnabled() = call("autoDriveEnabled") { autoDriveEnabled() }
    fun navigateTo(lat: Double?, lon: Double?, label: String?, query: String?) =
        call("navigateTo") { navigateTo(lat, lon, label, query) }
    fun backToHome() = call("backToHome") { backToHome() }

    /** A search; [done] gets the results on the main thread. */
    fun search(text: String, done: (List<CarPlace>) -> Unit) {
        val api = flutter ?: return done(emptyList())
        scope.launch {
            val found = try {
                api.search(text)
            } catch (e: Exception) {
                Log.w(TAG, "search failed: $e")
                emptyList()
            }
            done(found)
        }
    }

    // ------------------------------------------------------------- from Dart

    override fun ready() {
        dartReady = true
        connectedSurface?.let { surface -> call("connected") { connected(surface) } }
    }

    override fun setTexts(texts: Map<String, String>) {
        this.texts = texts
        each { onScreen() }
    }

    override fun setStyle(style: String, isJson: Boolean) {
        this.style = style
        styleIsJson = isJson
        each { onStyle() }
    }

    override fun registerImage(key: String, png: ByteArray, scale: Double) {
        val bitmap = BitmapFactory.decodeByteArray(png, 0, png.size) ?: return
        bitmap.density = (160 * scale).toInt()
        images[key] = bitmap
        each { onImage(key) }
    }

    override fun setRoutes(geoJson: String) {
        routesGeoJson = geoJson
        each { onRoutes() }
    }

    override fun setDriven(geoJson: String) {
        drivenGeoJson = geoJson
        each { onDriven() }
    }

    override fun setArrow(geoJson: String) {
        arrowGeoJson = geoJson
        each { onArrow() }
    }

    override fun setPosition(position: CarPosition) {
        this.position = position
        each { onPosition() }
    }

    override fun followCamera(camera: CarCamera) = each { onCamera(camera) }

    override fun fitBounds(bounds: CarBounds, paddingPx: Double) = each { onFitBounds(bounds, paddingPx) }

    override fun setFollowing(following: Boolean) {
        this.following = following
        each { onFollowing() }
    }

    override fun showHome(favourites: List<CarPlace>, recents: List<CarPlace>, locationOk: Boolean) {
        this.favourites = favourites
        this.recents = recents
        this.locationOk = locationOk
        homeShown = true
        screen = Screen.HOME
        loading = false
        message = null
        each { onScreen() }
    }

    override fun showRoutePreview(destinationLabel: String, routes: List<CarRouteSummary>, chosen: Long) {
        previewLabel = destinationLabel
        previewRoutes = routes
        previewChosen = chosen.toInt()
        screen = Screen.PREVIEW
        loading = false
        message = null
        each { onScreen() }
    }

    override fun showLoading(loading: Boolean) {
        this.loading = loading
        if (loading && screen == Screen.HOME) screen = Screen.PREVIEW
        each { onScreen() }
    }

    override fun showMessage(title: String, text: String) {
        message = title to text
        loading = false
        each { onScreen() }
    }

    override fun startNavigation(trip: CarTrip) {
        this.trip = trip
        maneuver = null
        arrivedAt = null
        recalculating = false
        screen = Screen.NAVIGATING
        message = null
        each { onScreen() }
    }

    override fun updateManeuver(next: CarManeuver, trip: CarTrip, speed: CarSpeed) {
        maneuver = next
        this.trip = trip
        this.speed = speed
        each { onScreen() }
    }

    override fun setRecalculating(recalculating: Boolean) {
        this.recalculating = recalculating
        each { onScreen() }
    }

    override fun showArrived(destinationLabel: String) {
        arrivedAt = destinationLabel
        screen = Screen.ARRIVED
        each { onScreen() }
    }

    override fun endNavigation() {
        trip = null
        maneuver = null
        speed = null
        arrivedAt = null
        alert = null
        screen = Screen.HOME
        each {
            onAlert(null)
            onScreen()
        }
    }

    override fun setMuted(muted: Boolean) {
        this.muted = muted
        each { onScreen() }
    }

    override fun showAlert(alert: CarAlert) {
        this.alert = alert
        each { onAlert(alert) }
    }

    override fun dismissAlert(id: String) {
        if (alert?.id != id) return
        alert = null
        each { onAlert(null) }
    }
}
