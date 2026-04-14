use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{ensure, Context};
use proto_gen::{SessionInfo, TaskStatus};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::config::default_sessions_path;
use crate::error::Result;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Session {
    pub id: String,
    pub name: String,
    pub status: i32,
    pub working_dir: String,
    pub created_at_ms: u64,
    pub last_active_ms: u64,
}

#[derive(Debug)]
pub struct SessionManager {
    sessions: HashMap<String, Session>,
    storage_path: PathBuf,
}

impl SessionManager {
    pub fn new(path: &Path) -> Result<Self> {
        Self::load_sync(path)
    }

    pub fn new_default() -> Result<Self> {
        Self::load_sync(&default_sessions_path())
    }

    pub fn get(&self, id: &str) -> Option<&Session> {
        self.sessions.get(id)
    }

    pub fn list(&self) -> Vec<SessionInfo> {
        self.sessions
            .values()
            .cloned()
            .map(SessionInfo::from)
            .collect()
    }

    pub fn create(&mut self, name: &str, working_dir: &str) -> Result<Session> {
        let now = now_ms();
        let session = Session {
            id: Uuid::new_v4().to_string(),
            name: name.to_owned(),
            status: TaskStatus::Idle as i32,
            working_dir: working_dir.to_owned(),
            created_at_ms: now,
            last_active_ms: now,
        };

        self.sessions.insert(session.id.clone(), session.clone());

        self.persist()?;

        Ok(session)
    }

    pub fn update_status(&mut self, id: &str, status: TaskStatus) -> Result<()> {
        self.try_update_status(id, status)
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

            serde_json::from_str(&contents).with_context(|| {
                format!(
                    "failed to parse session storage file at {}",
                    storage_path.display()
                )
            })?
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

    fn try_update_status(&mut self, id: &str, status: TaskStatus) -> Result<()> {
        if let Some(session) = self.sessions.get_mut(id) {
            session.status = status as i32;
            session.last_active_ms = now_ms();
            self.persist()?;
        }

        Ok(())
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should be after unix epoch")
        .as_millis() as u64
}

impl From<Session> for SessionInfo {
    fn from(session: Session) -> Self {
        Self {
            session_id: session.id,
            name: session.name,
            status: session.status,
            created_at_ms: session.created_at_ms,
            last_active_ms: session.last_active_ms,
            working_dir: session.working_dir,
        }
    }
}
