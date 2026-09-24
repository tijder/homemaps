package nl.g4d.homemaps

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import nl.g4d.homemaps.car.FlutterEngineHolder

class MainActivity : FlutterActivity() {
    /** The same engine as the car's (see [FlutterEngineHolder]). */
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        FlutterEngineHolder.get(context)

    override fun shouldDestroyEngineWithHost(): Boolean = false
}
