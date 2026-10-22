"""Adds what the background notifications need to the generated Android project.
Run by setup.sh after `flutter create`. Safe to run more than once."""
import re, shutil, sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
app = root / "android/app"
extra = Path(__file__).parent

# 1. Manifest: permissions + foreground service type for flutter_background_service
m = app / "src/main/AndroidManifest.xml"
s = m.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.WAKE_LOCK",
]
add = "".join(f'\n    <uses-permission android:name="{p}"/>' for p in perms if p not in s)
if add:
    s = re.sub(r"(<manifest[^>]*>)", lambda mm: mm.group(1) + add, s, count=1)
if "usesCleartextTraffic" not in s:
    s = s.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
if "flutter_background_service.BackgroundService" not in s:
    service = '''
        <!-- Vacuula: background watcher for notifications -->
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Watches the user's own robot vacuum on the home network"/>
        </service>
    </application>'''
    s = s.replace("    </application>", service, 1)
m.write_text(s)

# 2. Gradle: core library desugaring (required by flutter_local_notifications)
g = app / "build.gradle.kts"
if g.exists():
    s = g.read_text()
    if "isCoreLibraryDesugaringEnabled" not in s:
        s = s.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "desugar_jdk_libs" not in s:
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    g.write_text(s)
else:
    g = app / "build.gradle"
    s = g.read_text()
    if "coreLibraryDesugaringEnabled" not in s:
        s = s.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    if "desugar_jdk_libs" not in s:
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    g.write_text(s)

# 3. Notification icon (+ keep it in release builds)
for f in ("drawable/ic_stat_vacuula.xml", "raw/keep.xml"):
    dst = app / "src/main/res" / f
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(extra / "res" / f, dst)

print("    Android: notifications, background service and desugaring configured")
