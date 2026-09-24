package nl.g4d.homemaps.car.screens

import android.Manifest
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.PlaceListNavigationTemplate
import androidx.core.graphics.drawable.IconCompat
import nl.g4d.homemaps.R
import nl.g4d.homemaps.car.CarHost
import nl.g4d.homemaps.car.CarPlace

/**
 * The start: home, work and recent places over the map, with a search
 * button. Without a location the first row asks for permission (the
 * dialog appears on the phone).
 */
class HomeScreen(carContext: CarContext) : Screen(carContext), CarHost.Listener {
    init {
        CarHost.addListener(this)
        lifecycle.addObserver(object : androidx.lifecycle.DefaultLifecycleObserver {
            override fun onDestroy(owner: androidx.lifecycle.LifecycleOwner) = CarHost.removeListener(this@HomeScreen)
        })
    }

    override fun onScreen() = invalidate()

    private fun icon(resource: Int) = CarIcon.Builder(IconCompat.createWithResource(carContext, resource)).build()

    private fun row(place: CarPlace, resource: Int): Row =
        Row.Builder()
            .setTitle(place.label.ifEmpty { CarHost.text(place.kind) })
            .apply { if (place.detail.isNotEmpty()) addText(place.detail) }
            .setImage(icon(resource), Row.IMAGE_TYPE_ICON)
            .setBrowsable(true)
            .setOnClickListener { CarHost.placeChosen(place.id) }
            .build()

    @Suppress("DEPRECATION")
    override fun onGetTemplate(): Template {
        val builder = PlaceListNavigationTemplate.Builder()
            .setTitle(CarHost.text("whereTo"))
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setIcon(icon(R.drawable.ic_car_search))
                            .setOnClickListener { screenManager.push(SearchScreen(carContext)) }
                            .build(),
                    )
                    .build(),
            )
        if (!CarHost.homeShown) return builder.setLoading(true).build()
        val list = ItemList.Builder()
        if (!CarHost.locationOk) {
            list.addItem(
                Row.Builder()
                    .setTitle(CarHost.text("noLocation"))
                    .addText(CarHost.text("openApp"))
                    .setImage(icon(R.drawable.ic_car_location), Row.IMAGE_TYPE_ICON)
                    .setOnClickListener {
                        carContext.requestPermissions(listOf(Manifest.permission.ACCESS_FINE_LOCATION)) { _, _ -> }
                    }
                    .build(),
            )
        }
        for (place in CarHost.favourites) {
            list.addItem(row(place, if (place.kind == "work") R.drawable.ic_car_work else R.drawable.ic_car_home))
        }
        for (place in CarHost.recents) list.addItem(row(place, R.drawable.ic_car_history))
        if (CarHost.favourites.isEmpty() && CarHost.recents.isEmpty()) {
            list.setNoItemsMessage(CarHost.text("search"))
        }
        return builder.setItemList(list.build()).build()
    }
}
