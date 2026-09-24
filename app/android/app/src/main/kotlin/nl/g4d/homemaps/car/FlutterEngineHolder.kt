package nl.g4d.homemaps.car

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * The one Flutter engine of the app. The phone's activity and the car's
 * service share it: whoever comes first creates it, the other finds it in the
 * cache. A second engine would be a second app with its own state.
 */
object FlutterEngineHolder {
    const val ID = "main"

    fun get(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        GeneratedPluginRegistrant.registerWith(engine)
        // Before Dart runs, so its `ready()` finds the handlers in place.
        CarHostApi.setUp(engine.dartExecutor.binaryMessenger, CarHost)
        CarHost.attachEngine(engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }
}
