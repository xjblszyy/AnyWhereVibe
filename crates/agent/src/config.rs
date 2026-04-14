use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Config {
    pub server: ServerConfig,
    pub agent: AgentConfig,
    pub codex: CodexConfig,
    pub storage: StorageConfig,
    pub log: LogConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: ServerConfig::default(),
            agent: AgentConfig::default(),
            codex: CodexConfig::default(),
            storage: StorageConfig::default(),
            log: LogConfig::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ServerConfig {
    pub listen_addr: String,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            listen_addr: "0.0.0.0:9876".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AgentConfig {
    pub adapter: String,
    pub auto_fallback: bool,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            adapter: "codex-app-server".into(),
            auto_fallback: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CodexConfig {
    pub command: String,
    pub args: Vec<String>,
}

impl Default for CodexConfig {
    fn default() -> Self {
        Self {
            command: "codex".into(),
            args: vec!["app-server".into()],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StorageConfig {
    pub sessions_path: String,
}

impl Default for StorageConfig {
    fn default() -> Self {
        Self {
            sessions_path: default_sessions_path().to_string_lossy().into_owned(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LogConfig {
    pub level: String,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            level: "info".into(),
        }
    }
}

pub fn default_storage_dir() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("~"))
        .join(".mrt")
}

pub fn default_sessions_path() -> PathBuf {
    default_storage_dir().join("sessions.json")
}
