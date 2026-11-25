# التشغيل والصيانة

## البيئة
Flutter stable وDart المتوافق وAndroid SDK/JDK وGitHub Actions.

## أوامر التطوير
~~~bash
flutter doctor -v
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
~~~

## قاعدة البيانات
schema version واضح؛ migration لكل تعديل؛ فحص foreign keys بعد الاستعادة؛ لا تعدل قاعدة الإنتاج يدويًا؛ نسخة قبل migrations المدمرة.

## النسخ
snapshot متسق، schema version، checksum، تشفير عند اعتماد الآلية، اسم ملف لا يحتوي بيانات شخصية، واختبار restore دوري.

## الدعم
سجل تقني محدود، إخفاء الهواتف والأسماء والملاحظات، صفحة تشخيص بلا أسرار، وتصدير تشخيص بموافقة المستخدم.

## الإصدارات
SemVer MAJOR.MINOR.PATCH مع CHANGELOG لكل إصدار.
