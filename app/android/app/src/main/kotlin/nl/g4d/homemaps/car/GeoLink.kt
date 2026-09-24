package nl.g4d.homemaps.car

import android.net.Uri

/**
 * `geo:` links as the car sends them (the same forms as `utils/geo_link.dart`
 * on the phone): `geo:52.1,5.2`, `geo:0,0?q=52.1,5.2(Name)` and
 * `geo:0,0?q=Stationsplein 1, Utrecht`.
 */
object GeoLink {
    data class Request(val lat: Double?, val lon: Double?, val label: String?, val query: String?)

    private val numbers = Regex("""^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)""")
    private val labelAfterPoint = Regex("""\(([^)]*)\)\s*$""")

    private fun point(text: String): Pair<Double, Double>? {
        val m = numbers.find(text) ?: return null
        val lat = m.groupValues[1].toDouble()
        val lon = m.groupValues[2].toDouble()
        if (Math.abs(lat) > 90 || Math.abs(lon) > 180 || (lat == 0.0 && lon == 0.0)) return null
        return lat to lon
    }

    fun parse(uri: Uri): Request? {
        if (uri.scheme?.lowercase() != "geo") return null
        val raw = uri.toString().substring(4)
        val questionMark = raw.indexOf('?')
        val path = if (questionMark < 0) raw else raw.substring(0, questionMark)
        val query = if (questionMark < 0) "" else raw.substring(questionMark + 1)
        var q: String? = null
        for (part in query.split('&')) {
            val eq = part.indexOf('=')
            if (eq > 0 && part.substring(0, eq) == "q") {
                q = Uri.decode(part.substring(eq + 1)).trim()
            }
        }
        if (!q.isNullOrEmpty()) {
            point(q)?.let { (lat, lon) ->
                val label = labelAfterPoint.find(q)?.groupValues?.get(1)?.trim()
                return Request(lat, lon, label?.ifEmpty { null }, null)
            }
            return Request(null, null, null, q)
        }
        val p = point(Uri.decode(path)) ?: return null
        return Request(p.first, p.second, null, null)
    }
}
