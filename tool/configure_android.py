from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    raise SystemExit("Android manifest was not generated")

text = manifest.read_text(encoding="utf-8")
text = text.replace('android:label="advanced_assistant"', 'android:label="المساعد الذكي"')
text = text.replace('android:label="Advanced Assistant"', 'android:label="المساعد الذكي"')
permissions = [
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
    '    <uses-permission android:name="android.permission.VIBRATE" />',
]
for permission in permissions:
    if permission.split('"')[1] not in text:
        text = text.replace("<manifest", "<manifest", 1)
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
