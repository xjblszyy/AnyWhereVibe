use std::fs;
use std::path::Path;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserRecord {
    pub id: i64,
    pub name: String,
    pub token: String,
    pub active: bool,
    pub created_at: i64,
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
        let connection = self.connection.lock().expect("database mutex poisoned");
        connection.execute(
            "INSERT INTO users (name, token, active, created_at) VALUES (?1, ?2, 1, ?3)",
            params![name, token, now],
        )?;
        Ok(())
    }

    pub fn list_users(&self) -> Result<Vec<UserRecord>> {
        let connection = self.connection.lock().expect("database mutex poisoned");
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
        let connection = self.connection.lock().expect("database mutex poisoned");
        let changed =
            connection.execute("UPDATE users SET active = 0 WHERE name = ?1", params![name])?;
        if changed == 0 {
            return Err(anyhow!("user '{name}' not found"));
        }
        Ok(())
    }

    pub fn reset_user_token(&self, name: &str, token: &str) -> Result<()> {
        let connection = self.connection.lock().expect("database mutex poisoned");
        let changed = connection.execute(
            "UPDATE users SET token = ?1, active = 1 WHERE name = ?2",
            params![token, name],
        )?;
        if changed == 0 {
            return Err(anyhow!("user '{name}' not found"));
        }
        Ok(())
    }

    fn initialize(&self) -> Result<()> {
        let connection = self.connection.lock().expect("database mutex poisoned");
        connection.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL,
                token TEXT UNIQUE NOT NULL,
                active BOOLEAN DEFAULT 1,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS devices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER REFERENCES users(id),
                device_id TEXT UNIQUE NOT NULL,
                device_type INTEGER NOT NULL,
                display_name TEXT,
                last_seen INTEGER
            );
            "#,
        )?;
        Ok(())
    }
}

fn current_timestamp() -> Result<i64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() as i64)
}
