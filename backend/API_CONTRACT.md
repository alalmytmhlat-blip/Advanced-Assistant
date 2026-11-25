# عقد API المقترح لبوابة الذكاء

## POST /v1/assistant/respond
~~~json
{
  "conversation_id": "uuid",
  "message": "من العملاء الذين يحتاجون متابعة اليوم؟",
  "locale": "ar",
  "context": {"allowed_tools": ["list_overdue_followups"], "app_version": "0.1.0"}
}
~~~

استجابة typed مقترحة:
~~~json
{
  "response_id": "uuid",
  "answer": "وجدت ...",
  "intent": "query_followups",
  "tool_calls": [{"name": "list_overdue_followups", "arguments": {"range": "today", "limit": 50}}],
  "requires_confirmation": false,
  "evidence": [],
  "model": "provider-model-id"
}
~~~

قواعد العقد: تحقق schema؛ رفض الحقول غير المعروفة في الأوامر الحساسة؛ حدود للحجم والسياق والنتائج؛ لا أسرار في الاستجابة؛ لا تنفذ الكتابة من endpoint؛ يعيد الخادم خطة ثم يفرض التطبيق الصلاحية والتأكيد وينفذ Use Case المحلي؛ request_id وidempotency key؛ أخطاء موحدة؛ لا ترسل DB كاملة بل الحد الأدنى وبعد الموافقة.
