use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{ensure, Context};
use serde::{Deserialize, Serialize};

use crate::config::default_sessions_path;
use crate::error::Result;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Session {
    pub id: String,
    pub device_id: String,
    pub created_at_ms: u64,
    pub last_active_ms: u64,
}

#[derive(Debug)]
pub struct SessionManager {
    sessions: HashMap<String, Session>,
    storage_path: PathBuf,
}

impl SessionManager {
    pub async fn load(path: impl AsRef<Path>) -> Result<Self> {
        Self::load_sync(path.as_ref())
    }

    pub async fn load_default() -> Result<Self> {
        Self::load_sync(&default_sessions_path())
    }

    pub fn get(&self, id: &str) -> Option<&Session> {
        self.sessions.get(id)
    }

    pub async fn upsert_session(&mut self, id: String, device_id: String) -> Result<Session> {
        let now = now_ms();

        let session = self
            .sessions
            .entry(id.clone())
            .and_modify(|existing| {
                existing.device_id = device_id.clone();
                existing.last_active_ms = now;
            })
            .or_insert_with(|| Session {
                id,
                device_id,
                created_at_ms: now,
                last_active_ms: now,
            })
            .clone();

        self.persist()?;

        Ok(session)
    }

    fn load_sync(path: &Path) -> Result<Self> {
        let storage_path = path.to_path_buf();
        let parent = storage_path
            .parent()
            .context("session storage path must have a parent directory")?;

        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create session storage directory at {}",
                parent.display()
            )
        })?;

        let sessions = if storage_path.exists() {
            let contents = fs::read_to_string(&storage_path).with_context(|| {
                format!(
                    "failed to read session storage file at {}",
                    storage_path.display()
                )
            })?;

            if contents.trim().is_empty() {
                HashMap::new()
            } else {
                serde_json::from_str(&contents).with_context(|| {
                    format!(
                        "failed to parse session storage file at {}",
                        storage_path.display()
                    )
                })?
            }
        } else {
            HashMap::new()
        };

        Ok(Self {
            sessions,
            storage_path,
        })
    }

    fn persist(&self) -> Result<()> {
        let parent = self
            .storage_path
            .parent()
            .context("session storage path must have a parent directory")?;
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create session storage directory at {}",
                parent.display()
            )
        })?;

        let payload = serde_json::to_vec_pretty(&self.sessions)
            .context("failed to serialize session storage payload")?;

        let temp_path = self.temp_path();
        fs::write(&temp_path, payload).with_context(|| {
            format!(
                "failed to write temporary session storage file at {}",
                temp_path.display()
            )
        })?;

        ensure!(
            temp_path.exists(),
            "temporary session storage file was not created at {}",
            temp_path.display()
        );

        fs::rename(&temp_path, &self.storage_path).with_context(|| {
            format!(
                "failed to atomically replace session storage file at {}",
                self.storage_path.display()
            )
        })?;

        Ok(())
    }

    fn temp_path(&self) -> PathBuf {
        let mut file_name = self
            .storage_path
            .file_name()
            .map(|name| name.to_os_string())
            .unwrap_or_else(|| "sessions.json".into());
        file_name.push(".tmp");

        self.storage_path.with_file_name(file_name)
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should be after unix epoch")
        .as_millis() as u64
}
