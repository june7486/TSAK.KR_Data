package com.tsak.credentialmanager

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * TSAK.KR — MainActivity
 *
 * Flutter 기본 Activity 위에 "APK 자기 업데이트"용 MethodChannel 을 얹는다.
 *
 *   채널: "tsak/installer"
 *     · installApk(path)          : FileProvider content:// URI 로 패키지 설치 화면 호출
 *     · canRequestInstall()       : REQUEST_INSTALL_PACKAGES(설치 허용) 여부
 *     · openInstallSettings()     : '출처를 알 수 없는 앱 설치 허용' 설정 화면 열기
 *     · relaunch()                : 앱 재시작
 *
 * Android 8+ 에서는 file:// URI 를 직접 열 수 없어 FileProvider 가 필수다.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "tsak/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.sendResultSafe(installApk(path))
                    }
                    "canRequestInstall" -> {
                        result.sendResultSafe(canRequestInstall())
                    }
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "relaunch" -> {
                        relaunch()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 설치 허용(REQUEST_INSTALL_PACKAGES) 여부. O 미만은 항상 허용. */
    private fun canRequestInstall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    /** '출처를 알 수 없는 앱 설치' 설정 화면 열기 (O+). */
    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
        } catch (_: Exception) {
        }
    }

    /**
     * FileProvider 로 content:// URI 를 만들어 패키지 설치 화면을 띄운다.
     * @return 설치 화면을 성공적으로 열었으면 true.
     */
    private fun installApk(path: String): Boolean {
        if (path.isEmpty()) return false
        return try {
            val file = File(path)
            if (!file.exists()) return false

            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 앱 재시작(설치 완료 후 최신 코드 즉시 반영). */
    private fun relaunch() {
        try {
            val i = packageManager.getLaunchIntentForPackage(packageName)
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(i)
            }
            Runtime.getRuntime().exit(0)
        } catch (_: Exception) {
        }
    }

    /** 예외를 Flutter 로 안전 전달하고 null 은 false 로 정규화한다. */
    private fun MethodChannel.Result.sendResultSafe(v: Any?) {
        try {
            success(v)
        } catch (e: Exception) {
            error("E", e.message, null)
        }
    }
}
