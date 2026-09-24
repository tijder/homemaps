package nl.g4d.homemaps.car

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.car.app.CarContext
import androidx.car.app.notification.CarAppExtender
import androidx.car.app.notification.CarPendingIntent
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import nl.g4d.homemaps.R

/**
 * The turn-by-turn notification on the car (a requirement for navigation
 * apps): the next maneuver, updated as you drive. Android 13+ needs the
 * notification permission for it; without it there is simply none.
 */
object CarNotification {
    private const val CHANNEL = "car-navigation"
    private const val ID = 4711

    fun update(context: CarContext) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val maneuver = CarHost.maneuver ?: return
        val trip = CarHost.trip ?: return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, CarHost.text("routes"), NotificationManager.IMPORTANCE_HIGH),
            )
        }
        val open = CarPendingIntent.getCarApp(
            context,
            0,
            Intent(Intent.ACTION_VIEW).setComponent(context.startCarAppComponent()),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_car_navigation)
            .setContentTitle(Distance.format(maneuver.metersToNext) + " · " + maneuver.instruction)
            .setContentText(trip.destinationLabel)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .extend(
                CarAppExtender.Builder()
                    .setImportance(NotificationManager.IMPORTANCE_HIGH)
                    .setContentIntent(open)
                    .apply { CarHost.images[maneuver.iconKey]?.let { setLargeIcon(it) } }
                    .build(),
            )
        manager.notify(ID, builder.build())
    }

    fun clear(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(ID)
    }

    private fun CarContext.startCarAppComponent() =
        android.content.ComponentName(this, HomemapsCarAppService::class.java)
}
