package nl.g4d.homemaps.car.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.SearchTemplate
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import nl.g4d.homemaps.car.CarHost
import nl.g4d.homemaps.car.CarPlace

/** Type a place or address; Dart asks Photon and the rows come back here. */
class SearchScreen(carContext: CarContext) : Screen(carContext) {
    private var query = ""
    private var results: List<CarPlace> = emptyList()
    private var searching = false

    private fun search(text: String) {
        query = text
        if (text.trim().length < 2) {
            results = emptyList()
            invalidate()
            return
        }
        searching = true
        invalidate()
        CarHost.search(text) { found ->
            if (query != text) return@search
            results = found
            searching = false
            invalidate()
        }
    }

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        for (place in results) {
            list.addItem(
                Row.Builder()
                    .setTitle(place.label)
                    .apply { if (place.detail.isNotEmpty()) addText(place.detail) }
                    .setOnClickListener {
                        CarHost.placeChosen(place.id)
                        screenManager.pop()
                    }
                    .build(),
            )
        }
        if (results.isEmpty() && query.trim().length >= 2 && !searching) {
            list.setNoItemsMessage(CarHost.text("noResults"))
        }
        return SearchTemplate.Builder(object : SearchTemplate.SearchCallback {
            override fun onSearchTextChanged(searchText: String) = search(searchText)
            override fun onSearchSubmitted(searchText: String) = search(searchText)
        })
            .setHeaderAction(Action.BACK)
            .setSearchHint(CarHost.text("search"))
            .setShowKeyboardByDefault(true)
            .setLoading(searching)
            .setItemList(list.build())
            .build()
    }
}
