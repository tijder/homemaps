package nl.g4d.homemaps.car

import androidx.car.app.model.Distance as CarDistance
import java.util.Locale

/** Distances as the phone shows them: "650 m", "2.6 km", "15 km". */
object Distance {
    fun format(meters: Double): String = when {
        meters < 1000 -> "${meters.toInt()} m"
        meters < 10000 -> String.format(Locale.getDefault(), "%.1f km", meters / 1000)
        else -> "${(meters / 1000).toInt()} km"
    }

    /** The car's own distance, so the host formats it in the driver's units. */
    fun car(meters: Double): CarDistance = when {
        meters < 1000 -> CarDistance.create(meters, CarDistance.UNIT_METERS)
        meters < 10000 -> CarDistance.create(meters / 1000, CarDistance.UNIT_KILOMETERS_P1)
        else -> CarDistance.create(meters / 1000, CarDistance.UNIT_KILOMETERS)
    }

    /** "12 min", "1 h 05". */
    fun duration(seconds: Double): String {
        val minutes = (seconds / 60).toInt()
        if (minutes < 60) return "$minutes min"
        return "${minutes / 60} h ${String.format(Locale.ROOT, "%02d", minutes % 60)}"
    }
}
