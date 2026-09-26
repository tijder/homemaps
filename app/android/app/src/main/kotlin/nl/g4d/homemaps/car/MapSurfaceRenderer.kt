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
    private var root: FrameLayout? = null
    private var signs: Signs? = null
    private var matrix: MatrixView? = null
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
            root.setBackgroundColor(if (CarHost.styleDark) Color.rgb(0x1c, 0x1c, 0x1e) else Color.rgb(0xe0, 0xe0, 0xe0))
            root.addView(view, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            this.root = root
            if (name == "main") {
                root.addView(signsView(presentation.context))
                root.addView(matrixView(presentation.context))
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
        updateOverlays()
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

    private fun dp(value: Int) = (value * dpi / 160f).toInt()

    /** The views of the column at the bottom right. */
    private class Signs(
        val column: LinearLayout,
        val cameraBox: LinearLayout,
        val cameraIcon: ImageView,
        val cameraText: TextView,
        val cameraDetail: TextView,
        val limit: TextView,
        val speedBox: LinearLayout,
        val speedNumber: TextView,
        val speedUnit: TextView,
    )

    /**
     * The column at the bottom right of the visible area, as on the phone:
     * the next speed camera or the average speed check you're in (`CameraSign`
     * in `navigation_bar.dart`), the speed limit as a round sign (white on
     * black from the matrix signs), and your own speed, red when you're over.
     */
    private fun signsView(context: android.content.Context): View {
        val cameraIcon = ImageView(context)
        val cameraText = TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            setTypeface(null, android.graphics.Typeface.BOLD)
        }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(cameraIcon, LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginEnd = dp(6) })
            addView(cameraText)
        }
        val cameraDetail = TextView(context).apply {
            setTextColor(Color.argb(0xb3, 0xff, 0xff, 0xff))
            textSize = 11f
        }
        val cameraBox = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
            background = GradientDrawable().apply { cornerRadius = dp(10).toFloat() }
            addView(row)
            addView(cameraDetail)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(6) }
        }
        val limit = TextView(context).apply {
            gravity = Gravity.CENTER
            setTextColor(Color.BLACK)
            textSize = 24f
            setTypeface(null, android.graphics.Typeface.BOLD)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke(dp(6), Color.rgb(0xd3, 0x2f, 0x2f))
            }
            layoutParams = LinearLayout.LayoutParams(dp(64), dp(64)).apply { bottomMargin = dp(6) }
        }
        val speedNumber = TextView(context).apply {
            gravity = Gravity.CENTER
            textSize = 20f
            setTypeface(null, android.graphics.Typeface.BOLD)
        }
        val speedUnit = TextView(context).apply {
            gravity = Gravity.CENTER
            textSize = 11f
        }
        val speedBox = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            minimumWidth = dp(64)
            setPadding(dp(10), dp(4), dp(10), dp(4))
            background = GradientDrawable().apply { cornerRadius = dp(10).toFloat() }
            addView(speedNumber)
            addView(speedUnit)
        }
        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
            addView(cameraBox)
            addView(limit)
            addView(speedBox)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.END,
            )
        }
        signs = Signs(column, cameraBox, cameraIcon, cameraText, cameraDetail, limit, speedBox, speedNumber, speedUnit)
        updateOverlays()
        return column
    }

    private class MatrixView(val box: FrameLayout, val image: ImageView)

    /**
     * The matrix signs of the next gantry (MSI), as an image from Dart, at
     * the top of the visible area. The lanes themselves the host draws in
     * the routing card (see `NavigationScreen.step`).
     */
    private fun matrixView(context: android.content.Context): View {
        val image = ImageView(context).apply { adjustViewBounds = true }
        val box = FrameLayout(context).apply {
            addView(image, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, dp(44)))
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL,
            )
        }
        matrix = MatrixView(box, image)
        return box
    }

    /** The signs for what Dart sent last, inside the visible area. */
    private fun updateOverlays() {
        val area = visibleArea
        val margin = dp(12)
        val navigating = CarHost.screen == CarHost.Screen.NAVIGATING
        val speed = CarHost.speed
        signs?.let { s ->
            if (!navigating || speed == null) {
                s.column.visibility = View.GONE
            } else {
                val text = speed.cameraText
                s.cameraBox.visibility = if (text == null) View.GONE else View.VISIBLE
                if (text != null) {
                    s.cameraText.text = text
                    s.cameraDetail.text = speed.cameraDetail ?: ""
                    s.cameraDetail.visibility = if (speed.cameraDetail == null) View.GONE else View.VISIBLE
                    s.cameraIcon.setImageBitmap(speed.cameraIconKey?.let { CarHost.images[it] })
                    (s.cameraBox.background as? GradientDrawable)?.setColor(
                        if (speed.cameraOver) Color.rgb(0xd3, 0x2f, 0x2f) else Color.rgb(0x26, 0x32, 0x38),
                    )
                }
                val limit = speed.limitKmh
                s.limit.visibility = if (limit == null) View.GONE else View.VISIBLE
                if (limit != null) {
                    val msi = speed.limitSource == "msi"
                    s.limit.text = limit.toString()
                    s.limit.setTextColor(if (msi) Color.WHITE else Color.BLACK)
                    (s.limit.background as? GradientDrawable)?.setColor(if (msi) Color.BLACK else Color.WHITE)
                }
                val ms = speed.speedMs
                s.speedBox.visibility = if (ms == null) View.GONE else View.VISIBLE
                if (ms != null) {
                    val kmh = Math.round(ms * 3.6).toInt()
                    val speeding = limit != null && kmh > limit + 5
                    s.speedNumber.text = kmh.toString()
                    s.speedUnit.text = CarHost.text("kmh")
                    val color = if (speeding) Color.WHITE else Color.BLACK
                    s.speedNumber.setTextColor(color)
                    s.speedUnit.setTextColor(color)
                    (s.speedBox.background as? GradientDrawable)?.setColor(
                        if (speeding) Color.rgb(0xd3, 0x2f, 0x2f) else Color.WHITE,
                    )
                }
                s.column.visibility = View.VISIBLE
                (s.column.layoutParams as FrameLayout.LayoutParams).setMargins(
                    0,
                    0,
                    (width - (area?.right ?: width)) + margin,
                    (height - (area?.bottom ?: height)) + margin,
                )
                s.column.requestLayout()
            }
        }
        matrix?.let { m ->
            val bitmap = if (navigating) speed?.matrixIconKey?.let { CarHost.images[it] } else null
            m.box.visibility = if (bitmap == null) View.GONE else View.VISIBLE
            if (bitmap != null) {
                m.image.setImageBitmap(bitmap)
                (m.box.layoutParams as FrameLayout.LayoutParams).setMargins(
                    (area?.left ?: 0) + margin,
                    (area?.top ?: 0) + margin,
                    (width - (area?.right ?: width)) + margin,
                    0,
                )
                m.box.requestLayout()
            }
        }
    }

    private fun release() {
        signs = null
        matrix = null
        root = null
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
                PropertyFactory.iconSize(0.65f),
                PropertyFactory.iconRotate(Expression.get("bearing")),
                PropertyFactory.iconRotationAlignment("map"),
                PropertyFactory.iconAllowOverlap(true),
                PropertyFactory.iconIgnorePlacement(true),
            ).apply { setFilter(Expression.eq(Expression.geometryType(), "Point")) },
        )
        style.addLayer(
            SymbolLayer("position", "position").withProperties(
                PropertyFactory.iconImage("puck"),
                PropertyFactory.iconSize(0.65f),
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

    /**
     * Following: the position at three quarters of the height (the screen is
     * low, so as much road ahead as fits; the phone has two thirds). The same
     * in `CarPlayMapViewController.applyInsets`.
     */
    private fun applyPadding() {
        val map = map ?: return
        val area = visibleArea
        val top = (area?.top ?: 0) + if (CarHost.following) (height * 0.5).toInt() else 0
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

    override fun onStyle() {
        root?.setBackgroundColor(if (CarHost.styleDark) Color.rgb(0x1c, 0x1c, 0x1e) else Color.rgb(0xe0, 0xe0, 0xe0))
        loadStyle()
    }

    override fun onImage(key: String) {
        // A sign that was waiting for its image.
        if (key == CarHost.speed?.matrixIconKey || key == CarHost.speed?.cameraIconKey) updateOverlays()
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

    override fun onScreen() = updateOverlays()
    override fun onSpeed() = updateOverlays()
}
