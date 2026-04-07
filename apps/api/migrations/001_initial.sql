-- 지출 기록 테이블
CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY, -- UUIDv7 (client-generated)
    user_id TEXT NOT NULL, -- Supabase auth.users.id
    amount INTEGER NOT NULL, -- 원 단위 정수 (소수점 없음)
    date TEXT NOT NULL, -- YYYY-MM-DD
    category_id TEXT NOT NULL,
    memo TEXT,
    raw_utterance TEXT, -- 원문 자연어 (보존용)
    source TEXT NOT NULL DEFAULT 'form', -- 'form' | 'agent'
    deleted_at TEXT, -- soft delete: ISO8601 or NULL
    created_at TEXT NOT NULL DEFAULT(datetime('now')),
    updated_at TEXT NOT NULL DEFAULT(datetime('now'))
);

CREATE INDEX idx_transactions_user_date ON transactions (user_id, date)
WHERE
    deleted_at IS NULL;

CREATE INDEX idx_transactions_user_category ON transactions (user_id, category_id, date)
WHERE
    deleted_at IS NULL;

-- 감사 로그 테이블
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    action TEXT NOT NULL, -- 'insert' | 'soft_delete'
    record_id TEXT NOT NULL,
    payload TEXT, -- JSON snapshot
    created_at TEXT NOT NULL DEFAULT(datetime('now'))
);