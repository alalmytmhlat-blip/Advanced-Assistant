# نموذج البيانات المبدئي

هذا نموذج منطقي أولي يعتمد نهائيًا بعد مراجعة حالات الاستخدام.

- app_users: id, username, display_name, credential_hash/reference, role, is_active, timestamps.
- customers: id, name, phone, address, category, notes, current_balance, is_archived, timestamps.
- customer_notes: id, customer_id, body, created_by, created_at.
- contact_events: id, customer_id, contact_type, summary, outcome, occurred_at, created_by.
- followups: id, customer_id nullable, title, note, due_at, priority, status, assigned_to, reminder_id, created_by, timestamps, completed_at.
- inventory_items: id, original_name, original_code, original_size, unit, category_id, quantity, minimum_quantity, notes, is_archived, timestamps.
- inventory_categories: id, name, created_at.
- audit_events: id, actor_user_id, entity_type, entity_id, action, before_json, after_json, reason, occurred_at, operation_id.
- assistant_conversations: id, title, timestamps.
- assistant_messages: id, conversation_id, role, content, created_at, metadata_json بلا أسرار.
- app_settings: key, value_json, updated_at.
- schema_migrations: version, applied_at, checksum.

## قواعد البيانات
الرصيد signed ولا يخزن كنص منسق. استخدم تمثيلًا عشريًا دقيقًا (minor units عند دقة ثابتة أو decimal string مضبوط) ولا تستخدم double للأرصدة الدقيقة. الكمية بدقة ووحدة. فعّل foreign keys وindexes للاسم والهاتف والرمز وتاريخ المتابعة والحالة. timestamps UTC داخليًا. معاملات ذرية. الملفات خارج DB مع metadata.

## قواعد الرصيد
قيمة حالية مستقلة وليست دفتر قيود. كل تغيير يسجل السابق والجديد والفاعل والسبب. لا جداول payments أو invoices أو ledger. الاستيراد يحافظ على الإشارة ويطلب مراجعة القيم الملتبسة.

## قواعد الأصناف
original_name/code/size لا يعاد تنسيقها أو تصحيحها. يمكن إنشاء normalized_search منفصل. لا دمج تلقائي للأصناف المتشابهة.

كل تغيير schema يحتاج migration مرقمة واختبارًا على قاعدة فارغة ونسخة سابقة. لا إسقاط قبل خطة ترحيل ونسخة احتياطية.
