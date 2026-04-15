use std::fs;
use std::path::Path;
use std::sync::{Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserRecord {
    pub id: i64,
    pub name: String,
    pub token: String,
    pub active: bool,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceRecord {
    pub id: i64,
    pub user_id: i64,
    pub device_id: String,
    pub device_type: i32,
    pub display_name: Option<String>,
    pub last_seen_ms: Option<u64>,
}

pub struct Database {
    connection: Mutex<Connection>,
}

impl Database {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)?;
        }

        let connection = Connection::open(path)?;
        let database = Self {
            connection: Mutex::new(connection),
        };
        database.initialize()?;
        Ok(database)
    }

    pub fn open_in_memory() -> Result<Self> {
        let connection = Connection::open_in_memory()?;
        let database = Self {
            connection: Mutex::new(connection),
        };
        database.initialize()?;
        Ok(database)
    }

    pub fn insert_user(&self, name: &str, token: &str) -> Result<()> {
        let now = current_timestamp()?;
        let connection = self.connection()?;
        connection.execute(
            "INSERT INTO users (name, token, active, created_at) VALUES (?1, ?2, 1, ?3)",
            params![name, token, now],
        )?;
        Ok(())
    }

    pub fn list_users(&self) -> Result<Vec<UserRecord>> {
        let connection = self.connection()?;
        let mut statement = connection
            .prepare("SELECT id, name, token, active, created_at FROM users ORDER BY name ASC")?;
        let rows = statement.query_map([], |row| {
            Ok(UserRecord {
                id: row.get(0)?,
                name: row.get(1)?,
                token: row.get(2)?,
                active: row.get::<_, i64>(3)? != 0,
                created_at: row.get(4)?,
            })
        })?;

        let users = rows.collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(users)
    }

    pub fn revoke_user(&self, name: &str) -> Result<()> {
        let connection = self.connection()?;
        let changed =
            connection.execute("UPDATE users SET active = 0 WHERE name = ?1", params![name])?;
        if changed == 0 {
            return Err(anyhow!("user '{name}' not found"));
        }
        Ok(())
    }

    pub fn reset_user_token(&self, name: &str, token: &str) -> Result<()> {
        let connection = self.connection()?;
        let changed = connection.execute(
            "UPDATE users SET token = ?1, active = 1 WHERE name = ?2",
            params![token, name],
        )?;
        if changed == 0 {
            return Err(anyhow!("user '{name}' not found"));
        }
        Ok(())
    }

    pub fn find_active_user_by_token(&self, token: &str) -> Result<Option<UserRecord>> {
        let connection = self.connection()?;
        let mut statement = connection.prepare(
            "SELECT id, name, token, active, created_at FROM users WHERE token = ?1 AND active = 1",
        )?;
        let mut rows = statement.query(params![token])?;

        if let Some(row) = rows.next()? {
            return Ok(Some(UserRecord {
                id: row.get(0)?,
                name: row.get(1)?,
                token: row.get(2)?,
                active: row.get::<_, i64>(3)? != 0,
                created_at: row.get(4)?,
            }));
        }

        Ok(None)
    }

    pub fn upsert_device(
        &self,
        user_id: i64,
        device_id: &str,
        device_type: i32,
        display_name: &str,
    ) -> Result<()> {
        let connection = self.connection()?;
        connection.execute(
            r#"
            INSERT INTO devices (user_id, device_id, device_type, display_name, last_seen)
            VALUES (?1, ?2, ?3, ?4, NULL)
            ON CONFLICT(user_id, device_id) DO UPDATE SET
                device_type = excluded.device_type,
                display_name = excluded.display_name
            "#,
            params![user_id, device_id, device_type, display_name],
        )?;
        Ok(())
    }

    pub fn update_device_last_seen(
        &self,
        user_id: i64,
        device_id: &str,
        last_seen_ms: u64,
    ) -> Result<()> {
        let connection = self.connection()?;
        let changed = connection.execute(
            "UPDATE devices SET last_seen = ?1 WHERE user_id = ?2 AND device_id = ?3",
            params![last_seen_ms as i64, user_id, device_id],
        )?;
        if changed == 0 {
            return Err(anyhow!(
                "device '{device_id}' for user '{user_id}' not found"
            ));
        }
        Ok(())
    }

    pub fn list_devices_for_user(&self, user_id: i64) -> Result<Vec<DeviceRecord>> {
        let connection = self.connection()?;
        let mut statement = connection.prepare(
            r#"
            SELECT id, user_id, device_id, device_type, display_name, last_seen
            FROM devices
            WHERE user_id = ?1
            ORDER BY device_id ASC
            "#,
        )?;
        let rows = statement.query_map(params![user_id], |row| {
            let last_seen = row.get::<_, Option<i64>>(5)?;
            Ok(DeviceRecord {
                id: row.get(0)?,
                user_id: row.get(1)?,
                device_id: row.get(2)?,
                device_type: row.get(3)?,
                display_name: row.get(4)?,
                last_seen_ms: last_seen.map(|value| value as u64),
            })
        })?;

        let devices = rows.collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(devices)
    }

    fn initialize(&self) -> Result<()> {
        let connection = self.connection()?;
        connection.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL,
                token TEXT UNIQUE NOT NULL,
                active BOOLEAN DEFAULT 1,
                created_at INTEGER NOT NULL
            );
            "#,
        )?;
        ensure_devices_schema(&connection)?;
        Ok(())
    }

    fn connection(&self) -> Result<MutexGuard<'_, Connection>> {
        self.connection
            .lock()
            .map_err(|_| anyhow!("database mutex poisoned"))
    }
}

fn current_timestamp() -> Result<i64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() as i64)
}

fn ensure_devices_schema(connection: &Connection) -> Result<()> {
    let table_sql = connection
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'devices'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()?;

    match table_sql {
        None => {
            connection.execute_batch(
                r#"
                CREATE TABLE devices (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER REFERENCES users(id),
                    device_id TEXT NOT NULL,
                    device_type INTEGER NOT NULL,
                    display_name TEXT,
                    last_seen INTEGER
                );

                CREATE UNIQUE INDEX idx_devices_user_device ON devices(user_id, device_id);
                "#,
            )?;
        }
        Some(sql) if sql.contains("device_id TEXT UNIQUE NOT NULL") => {
            connection.execute_batch(
                r#"
                ALTER TABLE devices RENAME TO devices_legacy;

                CREATE TABLE devices (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER REFERENCES users(id),
                    device_id TEXT NOT NULL,
                    device_type INTEGER NOT NULL,
                    display_name TEXT,
                    last_seen INTEGER
                );

                CREATE UNIQUE INDEX idx_devices_user_device ON devices(user_id, device_id);

                INSERT INTO devices (id, user_id, device_id, device_type, display_name, last_seen)
                SELECT id, user_id, device_id, device_type, display_name, last_seen
                FROM devices_legacy;

                DROP TABLE devices_legacy;
                "#,
            )?;
        }
        Some(_) => {
            connection.execute_batch(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_user_device ON devices(user_id, device_id);",
            )?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use std::panic::{catch_unwind, AssertUnwindSafe};

    use super::Database;

    #[test]
    fn poisoned_mutex_returns_error_instead_of_panicking() {
        let db = Database::open_in_memory().expect("open db");

        let _ = catch_unwind(AssertUnwindSafe(|| {
            let _guard = db.connection.lock().expect("lock");
            panic!("poison mutex");
        }));

        let err = db.list_users().expect_err("poison should return an error");
        assert!(err.to_string().contains("database mutex poisoned"));
    }
}
