package nl.g4d.homemaps.car

import android.app.Presentation
import android.graphics.Point
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.util.Log
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.Layer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonSource
import kotlin.math.ln

/**
 * The map on the car's surface: a MapLibre [MapView] shown through a
 * [Presentation] on a virtual display that draws into the surface, as Google
 * documents for map apps. The routes, the driven part, the turn arrow and
 * the position come from Dart as GeoJSON and are drawn with the same colours
 * and widths as on the phone (see `map_widget.dart`).
 */
class MapSurfaceRenderer(private val carContext: CarContext, private val name: String) :
    SurfaceCallback, CarHost.Listener {

    companion object {
        private const val TAG = "MapSurfaceRenderer"
        private const val EMPTY = """{"type":"FeatureCollection","features":[]}"""
    }

    private var virtualDisplay: VirtualDisplay? = null
    private var presentation: Presentation? = null
    private var mapView: MapView? = null
    private var map: MapLibreMap? = null
    private var style: Style? = null
    private var visibleArea: Rect? = null
    private var speedLimit: TextView? = null
    private var cameraSign: CameraSign? = null
    private var width = 0
    private var height = 0
    private var dpi = 0

    /** The camera Dart asked for while the map wasn't ready yet. */
    private var pendingCamera: CarCamera? = null

    fun attach() {
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(this)
        CarHost.addListener(this)
        if (name == "main") MapSurfaceRendererRegistry.main = this
    }

    fun detach() {
        if (MapSurfaceRendererRegistry.main === this) MapSurfaceRendererRegistry.main = null
        CarHost.removeListener(this)
        release()
    }

    fun darkModeChanged() {
        report(first = false)
    }

    private fun report(first: Boolean) {
        if (width == 0 || name != "main") return
        val surface = CarSurface(
            width = width.toDouble(),
            height = height.toDouble(),
            density = dpi / 160.0,
            dark = carContext.isDarkMode,
            platform = "androidauto",
        )
        CarHost.surfaceAvailable(surface)
    }

    // ------------------------------------------------------------- surface

    override fun onSurfaceAvailable(container: SurfaceContainer) {
        val surface = container.surface ?: return
        if (container.width == 0 || container.height == 0) return
        release()
        width = container.width
        height = container.height
        dpi = container.dpi
        try {
            MapLibre.getInstance(carContext.applicationContext)
            val displayManager = carContext.getSystemService(DisplayManager::class.java)
            val display = displayManager.createVirtualDisplay(
                "homemaps-$name",
                width,
                height,
                dpi,
                surface,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
            )
            virtualDisplay = display
            val presentation = Presentation(carContext, display.display)
            val options = MapLibreMapOptions.createFromAttributes(carContext)
                .textureMode(true)
                .logoEnabled(false)
                .attributionEnabled(false)
                .compassEnabled(false)
            val view = MapView(presentation.context, options)
            mapView = view
            val root = FrameLayout(presentation.context)
            root.addView(view, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            if (name == "main") {
                root.addView(speedLimitView(presentation.context))
                root.addView(cameraSignView(presentation.context))
            }
            presentation.setContentView(root)
            this.presentation = presentation
            view.onCreate(null)
            view.onStart()
            view.onResume()
            presentation.show()
            view.getMapAsync { map ->
                this.map = map
                map.uiSettings.setAllGesturesEnabled(false)
                loadStyle()
            }
        } catch (e: Exception) {
            Log.e(TAG, "no map on the car's surface: $e")
            release()
        }
        report(first = true)
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        this.visibleArea = visibleArea
        applyPadding()
        updateSpeedLimit()
    }

    override fun onStableAreaChanged(stableArea: Rect) {}

    override fun onSurfaceDestroyed(container: SurfaceContainer) {
        release()
        width = 0
    }

    override fun onScroll(distanceX: Float, distanceY: Float) {
        map?.scrollBy(-distanceX, -distanceY)
        CarHost.userMovedMap()
    }

    override fun onFling(velocityX: Float, velocityY: Float) {}

    override fun onScale(focusX: Float, focusY: Float, scaleFactor: Float) {
        val map = map ?: return
        map.easeCamera(
            CameraUpdateFactory.zoomBy((ln(scaleFactor.toDouble()) / ln(2.0)), Point(focusX.toInt(), focusY.toInt())),
            100,
        )
        CarHost.userMovedMap()
    }

    /** The zoom buttons on the map. */
    fun zoom(steps: Double) {
        map?.easeCamera(CameraUpdateFactory.zoomBy(steps), 250)
        CarHost.userMovedMap()
    }

    /** The speed limit as a round sign, bottom left inside the visible area. */
    private fun speedLimitView(context: android.content.Context): View {
        val size = (56 * dpi / 160f).toInt()
        val view = TextView(context)
        view.gravity = Gravity.CENTER
        view.setTextColor(Color.BLACK)
        view.textSize = 20f
        view.setTypeface(null, android.graphics.Typeface.BOLD)
        view.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.WHITE)
            setStroke((5 * dpi / 160f).toInt(), Color.RED)
        }
        view.visibility = View.GONE
        view.layoutParams = FrameLayout.LayoutParams(size, size, Gravity.BOTTOM or Gravity.START)
        speedLimit = view
        updateSpeedLimit()
        return view
    }

    private fun updateSpeedLimit() {
        updateCameraSign()
        val view = speedLimit ?: return
        val limit = CarHost.speed?.limitKmh
        if (CarHost.screen != CarHost.Screen.NAVIGATING || limit == null) {
            view.visibility = View.GONE
            return
        }
        view.visibility = View.VISIBLE
        view.text = limit.toString()
        (view.background as? GradientDrawable)?.setStroke(
            ((if (CarHost.speed?.limitSource == "msi") 7 else 5) * dpi / 160f).toInt(),
            Color.RED,
        )
        val area = visibleArea
        val margin = (12 * dpi / 160f).toInt()
        (view.layoutParams as FrameLayout.LayoutParams).setMargins(
            (area?.left ?: 0) + margin,
            0,
            0,
            (height - (area?.bottom ?: height)) + margin,
        )
        view.requestLayout()
    }

    /** The views of the camera sign: the box, its icon and its two lines. */
    private class CameraSign(
        val box: LinearLayout,
        val icon: ImageView,
        val text: TextView,
        val detail: TextView,
    )

    /**
     * The next speed camera or the average speed check you're in, above the
     * speed limit, as on the phone (`CameraSign` in `navigation_bar.dart`).
     */
    private fun cameraSignView(context: android.content.Context): View {
        fun dp(value: Int) = (value * dpi / 160f).toInt()
        val icon = ImageView(context)
        val text = TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            setTypeface(null, android.graphics.Typeface.BOLD)
        }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(icon, LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginEnd = dp(6) })
            addView(text)
        }
        val detail = TextView(context).apply {
            setTextColor(Color.argb(0xb3, 0xff, 0xff, 0xff))
            textSize = 11f
        }
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = GradientDrawable().apply { cornerRadius = dp(10).toFloat() }
            addView(row)
            addView(detail)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.START,
            )
        }
        cameraSign = CameraSign(box, icon, text, detail)
        return box
    }

    private fun updateCameraSign() {
        val sign = cameraSign ?: return
        val speed = CarHost.speed
        val text = speed?.cameraText
        if (CarHost.screen != CarHost.Screen.NAVIGATING || text == null) {
            sign.box.visibility = View.GONE
            return
        }
        sign.box.visibility = View.VISIBLE
        sign.text.text = text
        sign.detail.text = speed.cameraDetail ?: ""
        sign.detail.visibility = if (speed.cameraDetail == null) View.GONE else View.VISIBLE
        sign.icon.setImageBitmap(speed.cameraIconKey?.let { CarHost.images[it] })
        (sign.box.background as? GradientDrawable)?.setColor(
            if (speed.cameraOver) Color.rgb(0xd3, 0x2f, 0x2f) else Color.rgb(0x26, 0x32, 0x38),
        )
        // Above the speed limit sign, or in its place when there is no limit.
        val area = visibleArea
        val margin = (12 * dpi / 160f).toInt()
        val limitHeight = if (speed.limitKmh == null) 0 else ((56 + 6) * dpi / 160f).toInt()
        (sign.box.layoutParams as FrameLayout.LayoutParams).setMargins(
            (area?.left ?: 0) + margin,
            0,
            0,
            (height - (area?.bottom ?: height)) + margin + limitHeight,
        )
        sign.box.requestLayout()
    }

    private fun release() {
        speedLimit = null
        cameraSign = null
        style = null
        map = null
        mapView?.let {
            it.onPause()
            it.onStop()
            it.onDestroy()
        }
        mapView = null
        presentation?.dismiss()
        presentation = null
        virtualDisplay?.release()
        virtualDisplay = null
    }

    // --------------------------------------------------------------- style

    private fun loadStyle() {
        val map = map ?: return
        val style = CarHost.style ?: return
        val builder = if (CarHost.styleIsJson) Style.Builder().fromJson(style) else Style.Builder().fromUri(style)
        map.setStyle(builder) { loaded ->
            this.style = loaded
            addLayers(loaded)
            for ((key, bitmap) in CarHost.images) loaded.addImage(key, bitmap)
            onRoutes()
            onDriven()
            onArrow()
            onPosition()
            pendingCamera?.let { onCamera(it) }
        }
    }

    /** The route lines below the map's names and road numbers. */
    private fun addLayers(style: Style) {
        val firstText: Layer? = style.layers.firstOrNull { it is SymbolLayer }
        fun add(layer: Layer) {
            if (firstText != null) style.addLayerBelow(layer, firstText.id) else style.addLayer(layer)
        }
        for (id in listOf("routes", "driven", "arrow", "position")) {
            style.addSource(GeoJsonSource(id, EMPTY))
        }
        fun line(id: String, source: String, color: String, width: Float, opacity: Float = 1f) =
            LineLayer(id, source).withProperties(
                PropertyFactory.lineColor(color),
                PropertyFactory.lineWidth(width),
                PropertyFactory.lineOpacity(opacity),
                PropertyFactory.lineCap("round"),
                PropertyFactory.lineJoin("round"),
            )
        add(line("route-alt", "routes", "#78909c", 5f, 0.8f).apply {
            setFilter(Expression.eq(Expression.get("chosen"), false))
        })
        add(line("route-casing", "routes", "#ffffff", 9f).apply {
            setFilter(Expression.eq(Expression.get("chosen"), true))
        })
        add(line("route", "routes", "#1565c0", 6f).apply {
            setFilter(Expression.eq(Expression.get("chosen"), true))
        })
        add(line("driven", "driven", "#9e9e9e", 6f))
        add(line("arrow-casing", "arrow", "#0d47a1", 11f))
        add(line("arrow", "arrow", "#ffffff", 6f))
        // The arrow head and the position dot above everything.
        style.addLayer(
            SymbolLayer("arrow-head", "arrow").withProperties(
                PropertyFactory.iconImage("arrow-head"),
                PropertyFactory.iconSize(0.5f),
                PropertyFactory.iconRotate(Expression.get("bearing")),
                PropertyFactory.iconRotationAlignment("map"),
                PropertyFactory.iconAllowOverlap(true),
                PropertyFactory.iconIgnorePlacement(true),
            ).apply { setFilter(Expression.eq(Expression.geometryType(), "Point")) },
        )
        style.addLayer(
            SymbolLayer("position", "position").withProperties(
                PropertyFactory.iconImage("puck"),
                PropertyFactory.iconSize(0.5f),
                PropertyFactory.iconRotate(Expression.get("heading")),
                PropertyFactory.iconRotationAlignment("map"),
                PropertyFactory.iconAllowOverlap(true),
                PropertyFactory.iconIgnorePlacement(true),
            ),
        )
    }

    private fun setGeoJson(source: String, geoJson: String?) {
        val style = style ?: return
        if (!style.isFullyLoaded) return
        style.getSourceAs<GeoJsonSource>(source)?.setGeoJson(geoJson ?: EMPTY)
    }

    /** Following: the position at two thirds of the height, as on the phone. */
    private fun applyPadding() {
        val map = map ?: return
        val area = visibleArea
        val top = (area?.top ?: 0) + if (CarHost.following) (height * 0.35).toInt() else 0
        map.easeCamera(
            CameraUpdateFactory.paddingTo(
                (area?.left ?: 0).toDouble(),
                top.toDouble(),
                (width - (area?.right ?: width)).toDouble(),
                (height - (area?.bottom ?: height)).toDouble(),
            ),
            0,
        )
    }

    // ---------------------------------------------------------------- Dart

    override fun onStyle() = loadStyle()

    override fun onImage(key: String) {
        val style = style ?: return
        val bitmap = CarHost.images[key] ?: return
        if (style.isFullyLoaded) style.addImage(key, bitmap)
    }

    override fun onRoutes() = setGeoJson("routes", CarHost.routesGeoJson)
    override fun onDriven() = setGeoJson("driven", CarHost.drivenGeoJson)
    override fun onArrow() = setGeoJson("arrow", CarHost.arrowGeoJson)

    override fun onPosition() {
        val p = CarHost.position ?: return setGeoJson("position", null)
        val heading = p.heading ?: 0.0
        setGeoJson(
            "position",
            """{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"heading":$heading},""" +
                """"geometry":{"type":"Point","coordinates":[${p.lon},${p.lat}]}}]}""",
        )
    }

    override fun onCamera(camera: CarCamera) {
        val map = map ?: run { pendingCamera = camera; return }
        if (style == null) { pendingCamera = camera; return }
        pendingCamera = null
        val position = CameraPosition.Builder()
            .target(LatLng(camera.lat, camera.lon))
            .zoom(camera.zoom)
            .bearing(camera.bearing)
            .tilt(camera.tilt)
            .build()
        val update = CameraUpdateFactory.newCameraPosition(position)
        if (camera.animateMs > 0) map.easeCamera(update, camera.animateMs.toInt(), false) else map.moveCamera(update)
    }

    override fun onFitBounds(bounds: CarBounds, paddingPx: Double) {
        val map = map ?: return
        val box = LatLngBounds.from(bounds.north, bounds.east, bounds.south, bounds.west)
        val padding = paddingPx.toInt()
        map.easeCamera(CameraUpdateFactory.newLatLngBounds(box, 0.0, 0.0, padding), 500)
    }

    override fun onFollowing() = applyPadding()

    override fun onScreen() = updateSpeedLimit()
}
