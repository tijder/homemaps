package nl.g4d.homemaps.car

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.validation.HostValidator
import android.content.pm.ApplicationInfo

/** Android Auto's entry point; the manifest declares it as a navigation app. */
class HomemapsCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(sessionInfo: SessionInfo): Session =
        if (sessionInfo.displayType == SessionInfo.DISPLAY_TYPE_CLUSTER) {
            ClusterSession()
        } else {
            HomemapsSession()
        }
}
