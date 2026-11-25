/// Versioned SQL schema for the local-first application database.
class DatabaseSchema {
  DatabaseSchema._();

  static const int version = 2;

  static const List<String> createStatements = [
    '''
    CREATE TABLE app_users (
      id TEXT PRIMARY KEY NOT NULL,
      username TEXT NOT NULL COLLATE NOCASE UNIQUE,
      display_name TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN (
        'manager', 'employee', 'inventory_manager', 'debt_collector'
      )),
      is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE customers (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      phone TEXT,
      address TEXT,
      category TEXT,
      notes TEXT,
      current_balance TEXT NOT NULL DEFAULT '0',
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE customer_notes (
      id TEXT PRIMARY KEY NOT NULL,
      customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      body TEXT NOT NULL,
      created_by TEXT REFERENCES app_users(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE contact_events (
      id TEXT PRIMARY KEY NOT NULL,
      customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      contact_type TEXT NOT NULL,
      summary TEXT NOT NULL,
      outcome TEXT,
      occurred_at TEXT NOT NULL,
      created_by TEXT REFERENCES app_users(id) ON DELETE SET NULL
    )
    ''',
    '''
    CREATE TABLE customer_balance_changes (
      id TEXT PRIMARY KEY NOT NULL,
      customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      previous_balance TEXT NOT NULL,
      new_balance TEXT NOT NULL,
      reason TEXT NOT NULL,
      changed_by TEXT REFERENCES app_users(id) ON DELETE SET NULL,
      changed_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE inventory_categories (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE inventory_items (
      id TEXT PRIMARY KEY NOT NULL,
      original_name TEXT NOT NULL,
      original_code TEXT,
      original_size TEXT,
      unit TEXT NOT NULL DEFAULT '',
      category_id TEXT REFERENCES inventory_categories(id) ON DELETE SET NULL,
      quantity TEXT NOT NULL DEFAULT '0',
      minimum_quantity TEXT NOT NULL DEFAULT '0',
      notes TEXT,
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE followups (
      id TEXT PRIMARY KEY NOT NULL,
      customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
      title TEXT NOT NULL,
      note TEXT,
      due_at TEXT NOT NULL,
      priority TEXT NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
      status TEXT NOT NULL DEFAULT 'new'
        CHECK (status IN ('new', 'scheduled', 'completed', 'postponed', 'cancelled')),
      assigned_to TEXT REFERENCES app_users(id) ON DELETE SET NULL,
      created_by TEXT REFERENCES app_users(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      completed_at TEXT
    )
    ''',
    '''
    CREATE TABLE audit_events (
      id TEXT PRIMARY KEY NOT NULL,
      actor_user_id TEXT REFERENCES app_users(id) ON DELETE SET NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT,
      action TEXT NOT NULL,
      before_json TEXT,
      after_json TEXT,
      reason TEXT,
      operation_id TEXT,
      occurred_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY NOT NULL,
      value_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE assistant_conversations (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE assistant_messages (
      id TEXT PRIMARY KEY NOT NULL,
      conversation_id TEXT NOT NULL
        REFERENCES assistant_conversations(id) ON DELETE CASCADE,
      role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'tool')),
      content TEXT NOT NULL,
      metadata_json TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    ...migrationV2Statements,
    'CREATE INDEX idx_customers_name ON customers(name COLLATE NOCASE)',
    'CREATE INDEX idx_customers_phone ON customers(phone)',
    'CREATE INDEX idx_customers_archived ON customers(is_archived)',
    'CREATE INDEX idx_followups_due_status ON followups(due_at, status)',
    'CREATE INDEX idx_followups_assignee ON followups(assigned_to, due_at)',
    'CREATE INDEX idx_inventory_name ON inventory_items(original_name COLLATE NOCASE)',
    'CREATE INDEX idx_inventory_code ON inventory_items(original_code)',
    'CREATE INDEX idx_inventory_category ON inventory_items(category_id)',
    'CREATE INDEX idx_balance_changes_customer ON customer_balance_changes(customer_id, changed_at)',
    'CREATE INDEX idx_audit_entity ON audit_events(entity_type, entity_id, occurred_at)',
    'CREATE INDEX idx_assistant_messages_conversation ON assistant_messages(conversation_id, created_at)',
  ];

  /// Additive migration: permissions are explicit grants and customer scopes
  /// are allow-lists. Existing users retain their role; no data is discarded.
  static const List<String> migrationV2Statements = [
    '''
    CREATE TABLE user_permissions (
      id TEXT PRIMARY KEY NOT NULL,
      user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      permission TEXT NOT NULL,
      granted_by TEXT REFERENCES app_users(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL,
      UNIQUE(user_id, permission)
    )
    ''',
    '''
    CREATE TABLE user_customer_scopes (
      user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      customer_id TEXT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      assigned_by TEXT REFERENCES app_users(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(user_id, customer_id)
    )
    ''',
    'CREATE INDEX idx_user_permissions_user ON user_permissions(user_id)',
    'CREATE INDEX idx_user_customer_scopes_customer ON user_customer_scopes(customer_id)',
  ];
}
