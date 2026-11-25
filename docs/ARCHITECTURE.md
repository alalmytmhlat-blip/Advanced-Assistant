# المعمارية التقنية

## المبادئ
Local-first؛ SQLite مصدر البيانات المحلي في V1؛ فصل العرض عن الأعمال والبيانات؛ ميزات مستقلة؛ حقن اعتماديات؛ لا اتصال مباشر من الواجهة إلى مزود AI؛ كل كتابة تمر عبر Use Case وصلاحيات وتحقق وتدقيق؛ migrations مختبرة.

## الطبقات
1. Presentation: صفحات Flutter وWidgets والحالة.
2. Application: Use Cases وDTOs والتنسيق والتحقق.
3. Domain: Entities وValue Objects وعقود المستودعات والسياسات.
4. Data: SQLite DAOs وتنفيذ المستودعات والاستيراد والإشعارات.
5. Infrastructure: logging والملفات وAI gateway والمنصة.

## التقنيات
Flutter/Dart stable؛ SQLite خلف Repository مع اختيار ORM بعد اختبار؛ حل حالة واحد (Riverpod أو غيره)؛ Router مركزي؛ نماذج typed؛ AI Gateway مستقل؛ GitHub Actions. راجع صيانة وترخيص وتوافق أي dependency قبل إضافتها.

## هيكل Flutter
~~~text
lib/
  main.dart
  app/{app.dart,router.dart,app_providers.dart}
  core/{config,database,errors,logging,security,theme,localization,notifications,files,utils}/
  shared/{widgets,models,validators}/
  features/
    dashboard/{data,domain,presentation}/
    customers/{data,domain,presentation}/
    balances/{data,domain,presentation}/
    inventory/{data,domain,presentation}/
    reminders/{data,domain,presentation}/
    reports/{data,domain,presentation}/
    assistant/{data,domain,presentation}/
    users/{data,domain,presentation}/
    pdf_import/{data,domain,presentation}/
    backup/{data,domain,presentation}/
test/{unit,widget,integration}/
integration_test/
backend/{README.md,API_CONTRACT.md}
~~~

## تدفق البيانات
واجهة ← Use Case ← فحص الصلاحية ← Domain Policy ← Repository ← SQLite ← نتيجة typed. الكتابات الحساسة تسجل Audit Event ضمن transaction قدر الإمكان.

## حدود الخادم
في V1 الخادم لبوابة AI فقط، وليس مصدر بيانات التطبيق. لا SQL مباشر للنموذج ولا تجاوز للصلاحيات. لا مزامنة أجهزة دون قرار مستقل. الأخطاء مفهومة، والمعاملات ذرية، ولا retries للكتابات غير idempotent.
