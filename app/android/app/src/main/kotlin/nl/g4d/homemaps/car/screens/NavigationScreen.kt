package nl.g4d.homemaps.car.screens

import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.Alert
import androidx.car.app.model.AlertCallback
import android.text.SpannableString
import android.text.Spanned
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarIconSpan
import androidx.car.app.model.CarText
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.model.Destination
import androidx.car.app.navigation.model.Lane
import androidx.car.app.navigation.model.LaneDirection
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.navigation.model.Trip
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import nl.g4d.homemaps.R
import nl.g4d.homemaps.car.CarAlert
import nl.g4d.homemaps.car.CarHost
import nl.g4d.homemaps.car.CarLane
import nl.g4d.homemaps.car.CarManeuver
import nl.g4d.homemaps.car.CarManeuverType
import nl.g4d.homemaps.car.CarNotification
import nl.g4d.homemaps.car.Distance
import nl.g4d.homemaps.car.MapSurfaceRendererRegistry
import java.util.TimeZone

/**
 * Turn-by-turn: the next maneuver with its icon and lanes, the ETA, stop
 * and mute, and pan/zoom on the map. On the cluster the same without
 * anything to press.
 */
class NavigationScreen(carContext: CarContext, private val cluster: Boolean = false) :
    Screen(carContext), CarHost.Listener {

    init {
        CarHost.addListener(this)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) = CarHost.removeListener(this@NavigationScreen)
        })
        setMarker("navigation")
    }

    private fun icon(resource: Int) = CarIcon.Builder(IconCompat.createWithResource(carContext, resource)).build()

    private fun bitmapIcon(key: String?): CarIcon? =
        key?.let { CarHost.images[it] }?.let { CarIcon.Builder(IconCompat.createWithBitmap(it)).build() }

    override fun onScreen() {
        invalidate()
        if (!cluster) {
            CarNotification.update(carContext)
            updateTrip()
        }
    }

    override fun onAlert(alert: CarAlert?) {
        if (cluster || alert == null) return
        if (carContext.carAppApiLevel < 5) {
            CarToast.makeText(carContext, "${alert.title} ${alert.text}", CarToast.LENGTH_LONG).show()
            return
        }
        val built = Alert.Builder(alert.id.hashCode(), CarText.create(alert.title), alert.seconds * 1000L)
            .setSubtitle(CarText.create(alert.text))
            .addAction(
                Action.Builder().setTitle(alert.accept).setOnClickListener { CarHost.alertAnswered(alert.id, true) }.build(),
            )
            .addAction(
                Action.Builder().setTitle(alert.reject).setOnClickListener { CarHost.alertAnswered(alert.id, false) }.build(),
            )
            .setCallback(object : AlertCallback {
                override fun onCancel(reason: Int) {}
                override fun onDismiss() {}
            })
            .build()
        carContext.getCarService(AppManager::class.java).showAlert(built)
    }

    /** What the host and the cluster get through the navigation manager. */
    private fun updateTrip() {
        val trip = CarHost.trip ?: return
        val estimate = travelEstimate() ?: return
        val builder = Trip.Builder()
            .addDestination(Destination.Builder().setName(trip.destinationLabel).build(), estimate)
        CarHost.maneuver?.let { builder.addStep(step(it), stepEstimate(it)) }
        builder.setLoading(CarHost.recalculating)
        carContext.getCarService(NavigationManager::class.java).updateTrip(builder.build())
    }

    private fun travelEstimate(): TravelEstimate? {
        val trip = CarHost.trip ?: return null
        return TravelEstimate.Builder(
            Distance.car(trip.remainingMeters),
            DateTimeWithZone.create(trip.etaEpochMs, TimeZone.getDefault()),
        )
            .setRemainingTimeSeconds(trip.remainingSeconds.toLong())
            .build()
    }

    private fun stepEstimate(m: CarManeuver): TravelEstimate =
        TravelEstimate.Builder(
            Distance.car(m.metersToNext),
            DateTimeWithZone.create(System.currentTimeMillis(), TimeZone.getDefault()),
        ).build()

    private fun maneuver(m: CarManeuver): Maneuver {
        val type = androidType(m)
        val builder = Maneuver.Builder(type)
        if (type == Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW_WITH_ANGLE ||
            type == Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW
        ) {
            builder.setRoundaboutExitNumber((m.roundaboutExit ?: 1).toInt().coerceAtLeast(1))
            if (type == Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW_WITH_ANGLE) {
                builder.setRoundaboutExitAngle((m.roundaboutAngle ?: 90.0).toInt().coerceIn(1, 360))
            }
        }
        bitmapIcon(m.iconKey)?.let { builder.setIcon(it) }
        return builder.build()
    }

    private fun androidType(m: CarManeuver): Int = when (m.type) {
        CarManeuverType.DEPART -> Maneuver.TYPE_DEPART
        CarManeuverType.DESTINATION -> Maneuver.TYPE_DESTINATION
        CarManeuverType.DESTINATION_LEFT -> Maneuver.TYPE_DESTINATION_LEFT
        CarManeuverType.DESTINATION_RIGHT -> Maneuver.TYPE_DESTINATION_RIGHT
        CarManeuverType.STRAIGHT, CarManeuverType.KEEP_STRAIGHT, CarManeuverType.ON_RAMP_STRAIGHT -> Maneuver.TYPE_STRAIGHT
        CarManeuverType.NAME_CHANGE -> Maneuver.TYPE_NAME_CHANGE
        CarManeuverType.SLIGHT_RIGHT -> Maneuver.TYPE_TURN_SLIGHT_RIGHT
        CarManeuverType.RIGHT -> Maneuver.TYPE_TURN_NORMAL_RIGHT
        CarManeuverType.SHARP_RIGHT -> Maneuver.TYPE_TURN_SHARP_RIGHT
        CarManeuverType.UTURN_RIGHT -> Maneuver.TYPE_U_TURN_RIGHT
        CarManeuverType.UTURN_LEFT -> Maneuver.TYPE_U_TURN_LEFT
        CarManeuverType.SHARP_LEFT -> Maneuver.TYPE_TURN_SHARP_LEFT
        CarManeuverType.LEFT -> Maneuver.TYPE_TURN_NORMAL_LEFT
        CarManeuverType.SLIGHT_LEFT -> Maneuver.TYPE_TURN_SLIGHT_LEFT
        CarManeuverType.ON_RAMP_RIGHT -> Maneuver.TYPE_ON_RAMP_SLIGHT_RIGHT
        CarManeuverType.ON_RAMP_LEFT -> Maneuver.TYPE_ON_RAMP_SLIGHT_LEFT
        CarManeuverType.OFF_RAMP_RIGHT -> Maneuver.TYPE_OFF_RAMP_SLIGHT_RIGHT
        CarManeuverType.OFF_RAMP_LEFT -> Maneuver.TYPE_OFF_RAMP_SLIGHT_LEFT
        CarManeuverType.KEEP_RIGHT -> Maneuver.TYPE_KEEP_RIGHT
        CarManeuverType.KEEP_LEFT -> Maneuver.TYPE_KEEP_LEFT
        CarManeuverType.MERGE -> Maneuver.TYPE_MERGE_SIDE_UNSPECIFIED
        CarManeuverType.MERGE_RIGHT -> Maneuver.TYPE_MERGE_RIGHT
        CarManeuverType.MERGE_LEFT -> Maneuver.TYPE_MERGE_LEFT
        CarManeuverType.ROUNDABOUT ->
            if (m.roundaboutAngle != null) Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW_WITH_ANGLE
            else Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW
        CarManeuverType.ROUNDABOUT_EXIT -> Maneuver.TYPE_ROUNDABOUT_EXIT_CCW
        CarManeuverType.FERRY_ENTER, CarManeuverType.FERRY_EXIT -> Maneuver.TYPE_FERRY_BOAT
    }

    private fun laneShape(direction: String): Int = when (direction) {
        "slight right" -> LaneDirection.SHAPE_SLIGHT_RIGHT
        "right" -> LaneDirection.SHAPE_NORMAL_RIGHT
        "sharp right" -> LaneDirection.SHAPE_SHARP_RIGHT
        "slight left" -> LaneDirection.SHAPE_SLIGHT_LEFT
        "left" -> LaneDirection.SHAPE_NORMAL_LEFT
        "sharp left" -> LaneDirection.SHAPE_SHARP_LEFT
        "uturn" -> LaneDirection.SHAPE_U_TURN_LEFT
        else -> LaneDirection.SHAPE_STRAIGHT
    }

    private fun lane(lane: CarLane): Lane {
        val builder = Lane.Builder()
        val directions = lane.directions.ifEmpty { listOf("straight") }
        for (direction in directions) {
            builder.addDirection(LaneDirection.create(laneShape(direction), lane.correct && (lane.usage == null || lane.usage == direction)))
        }
        return builder.build()
    }

    /**
     * At an exit: briefly what you do, with the sign (exit number, road
     * shields, directions) as an image after it, as the phone's header.
     */
    private fun cue(m: CarManeuver): CharSequence {
        val text = m.shortAction ?: m.instruction
        val sign = bitmapIcon(m.signIconKey) ?: return text
        val cue = SpannableString("$text  ")
        cue.setSpan(CarIconSpan.create(sign, CarIconSpan.ALIGN_CENTER), cue.length - 1, cue.length, Spanned.SPAN_INCLUSIVE_EXCLUSIVE)
        return cue
    }

    private fun step(m: CarManeuver): Step {
        val builder = Step.Builder(cue(m))
            .setManeuver(maneuver(m))
        if (m.streets.isNotEmpty()) builder.setRoad(m.streets.joinToString(", "))
        m.lanes?.let { lanes ->
            for (l in lanes) builder.addLane(lane(l))
            bitmapIcon(m.lanesIconKey)?.let { builder.setLanesImage(it) }
        }
        return builder.build()
    }

    companion object {
        /** The app's blue behind the instructions, as on CarPlay and the phone's header. */
        val panelColor: CarColor = CarColor.createCustom(0xFF1565C0.toInt(), 0xFF0D47A1.toInt())
    }

    override fun onGetTemplate(): Template {
        val builder = NavigationTemplate.Builder().setBackgroundColor(panelColor)
        val arrived = CarHost.arrivedAt
        val next = CarHost.maneuver
        when {
            arrived != null -> builder.setNavigationInfo(
                MessageInfo.Builder(CarHost.text("arrived")).setText(arrived).setImage(icon(R.drawable.ic_car_flag)).build(),
            )
            CarHost.recalculating -> builder.setNavigationInfo(
                MessageInfo.Builder(CarHost.text("recalculating")).setImage(icon(R.drawable.ic_car_sync)).build(),
            )
            next != null -> {
                val info = RoutingInfo.Builder()
                    .setCurrentStep(step(next), Distance.car(next.metersToNext))
                next.then.firstOrNull()?.let { info.setNextStep(step(it)) }
                builder.setNavigationInfo(info.build())
            }
            else -> builder.setNavigationInfo(RoutingInfo.Builder().setLoading(true).build())
        }
        travelEstimate()?.let { builder.setDestinationTravelEstimate(it) }
        if (!cluster) {
            val strip = ActionStrip.Builder()
            if (arrived != null) {
                strip.addAction(
                    Action.Builder().setTitle(CarHost.text("stop")).setOnClickListener { CarHost.stopTrip() }.build(),
                )
            } else {
                strip.addAction(
                    Action.Builder()
                        .setIcon(icon(if (CarHost.muted) R.drawable.ic_car_unmute else R.drawable.ic_car_mute))
                        .setOnClickListener { CarHost.toggleMute() }
                        .build(),
                )
                strip.addAction(
                    Action.Builder()
                        .setTitle(CarHost.text("stop"))
                        .setBackgroundColor(CarColor.RED)
                        .setOnClickListener { CarHost.stopTrip() }
                        .build(),
                )
            }
            builder.setActionStrip(strip.build())
            val renderer = MapSurfaceRendererRegistry.main
            builder.setMapActionStrip(
                ActionStrip.Builder()
                    .addAction(Action.PAN)
                    .addAction(
                        Action.Builder().setIcon(icon(R.drawable.ic_car_recenter)).setOnClickListener { CarHost.recenter() }.build(),
                    )
                    .addAction(
                        Action.Builder().setIcon(icon(R.drawable.ic_car_zoom_in)).setOnClickListener { renderer?.zoom(1.0) }.build(),
                    )
                    .addAction(
                        Action.Builder().setIcon(icon(R.drawable.ic_car_zoom_out)).setOnClickListener { renderer?.zoom(-1.0) }.build(),
                    )
                    .build(),
            )
            builder.setPanModeListener { panning -> if (panning) CarHost.userMovedMap() }
        }
        return builder.build()
    }
}
