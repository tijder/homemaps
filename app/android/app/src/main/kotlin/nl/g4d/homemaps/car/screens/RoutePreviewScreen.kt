package nl.g4d.homemaps.car.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.ItemList
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.RoutePreviewNavigationTemplate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import nl.g4d.homemaps.car.CarHost
import nl.g4d.homemaps.car.Distance

/** The routes to the chosen place: pick one and start. */
class RoutePreviewScreen(carContext: CarContext) : Screen(carContext), CarHost.Listener {
    init {
        CarHost.addListener(this)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) = CarHost.removeListener(this@RoutePreviewScreen)
        })
        setMarker("preview")
    }

    override fun onScreen() = invalidate()

    @Suppress("DEPRECATION")
    override fun onGetTemplate(): Template {
        CarHost.message?.let { (title, text) ->
            return MessageTemplate.Builder(text.ifEmpty { title })
                .setTitle(title)
                .setHeaderAction(Action.BACK)
                .addAction(
                    Action.Builder()
                        .setTitle(CarHost.text("whereTo"))
                        .setOnClickListener { CarHost.backToHome() }
                        .build(),
                )
                .build()
        }
        val builder = RoutePreviewNavigationTemplate.Builder()
            .setTitle(CarHost.previewLabel.ifEmpty { CarHost.text("routes") })
            .setHeaderAction(Action.BACK)
        if (CarHost.loading || CarHost.previewRoutes.isEmpty()) return builder.setLoading(true).build()
        val list = ItemList.Builder()
            .setOnSelectedListener { index -> CarHost.routeChosen(index.toLong()) }
            .setSelectedIndex(CarHost.previewChosen.coerceIn(0, CarHost.previewRoutes.size - 1))
        for (route in CarHost.previewRoutes) {
            val details = mutableListOf(Distance.format(route.meters))
            if (route.via.isNotEmpty()) details.add(route.via)
            if (route.delaySeconds >= 60) details.add("+${Distance.duration(route.delaySeconds)} ${CarHost.text("delay")}")
            if (route.hasToll) details.add(CarHost.text("toll"))
            if (route.hasFerry) details.add(CarHost.text("ferry"))
            list.addItem(
                Row.Builder()
                    .setTitle(Distance.duration(route.seconds))
                    .addText(details.joinToString(" · "))
                    .build(),
            )
        }
        return builder
            .setItemList(list.build())
            .setNavigateAction(
                Action.Builder()
                    .setTitle(CarHost.text("start"))
                    .setBackgroundColor(CarColor.BLUE)
                    .setOnClickListener { CarHost.startTrip() }
                    .build(),
            )
            .build()
    }
}
