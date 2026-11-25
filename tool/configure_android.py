import re
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    raise SystemExit("Android manifest was not generated")

text = manifest.read_text(encoding="utf-8")
text = re.sub(r'(android:label=")[^"]*(")', r'\1المساعد الذكي\2', text, count=1)
permissions = [
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
    '    <uses-permission android:name="android.permission.VIBRATE" />',
]
for permission in permissions:
    permission_name = permission.split('"')[1]
    if permission_name not in text:
        marker = text.find(">", text.find("<manifest"))
        text = text[:marker + 1] + "\n" + permission + text[marker + 1:]

receivers = '''
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
            android:exported="false" />
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
            android:enabled="true"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
'''
if "ScheduledNotificationReceiver" not in text:
    text = text.replace("</application>", receivers + "\n    </application>")
manifest.write_text(text, encoding="utf-8")

gradle_candidates = [
    Path("android/app/build.gradle.kts"),
    Path("android/app/build.gradle"),
]
app_gradle = next((path for path in gradle_candidates if path.exists()), None)
if app_gradle is None:
    raise SystemExit("Android app Gradle file was not generated")

gradle_text = app_gradle.read_text(encoding="utf-8")
if app_gradle.suffix == ".kts":
    if "isCoreLibraryDesugaringEnabled" not in gradle_text:
        pattern = r"(compileOptions\s*\{)"
        if not re.search(pattern, gradle_text):
            raise SystemExit("compileOptions block not found in Kotlin Gradle file")
        gradle_text = re.sub(pattern, r"\1\n        isCoreLibraryDesugaringEnabled = true", gradle_text, count=1)
    dependency = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")'
    if dependency not in gradle_text:
        pattern = r"(dependencies\s*\{)"
        if not re.search(pattern, gradle_text):
            gradle_text += "\n\ndependencies {\n    " + dependency + "\n}\n"
        else:
            gradle_text = re.sub(pattern, r"\1\n    " + dependency, gradle_text, count=1)
else:
    if "coreLibraryDesugaringEnabled" not in gradle_text:
        pattern = r"(compileOptions\s*\{)"
        if not re.search(pattern, gradle_text):
            raise SystemExit("compileOptions block not found in Groovy Gradle file")
        gradle_text = re.sub(pattern, r"\1\n        coreLibraryDesugaringEnabled true", gradle_text, count=1)
    dependency = "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.5'"
    if dependency not in gradle_text:
        pattern = r"(dependencies\s*\{)"
        if not re.search(pattern, gradle_text):
            gradle_text += "\n\ndependencies {\n    " + dependency + "\n}\n"
        else:
            gradle_text = re.sub(pattern, r"\1\n    " + dependency, gradle_text, count=1)

app_gradle.write_text(gradle_text, encoding="utf-8")
