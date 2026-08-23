CREATE TABLE IF NOT EXISTS crash_signatures (
    fingerprint TEXT PRIMARY KEY,
    component TEXT NOT NULL,
    normalized_error TEXT NOT NULL,
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    first_version TEXT,
    last_version TEXT,
    occurrence_count INTEGER NOT NULL DEFAULT 1,
    github_issue_number INTEGER,
    github_issue_url TEXT,
    status TEXT NOT NULL DEFAULT 'open'
);

CREATE INDEX IF NOT EXISTS idx_crash_signatures_last_seen
ON crash_signatures(last_seen);

CREATE INDEX IF NOT EXISTS idx_crash_signatures_issue
ON crash_signatures(github_issue_number);
