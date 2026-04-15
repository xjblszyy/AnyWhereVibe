use std::fs;
use std::path::{Path, PathBuf};

use anyhow::Result;
use serde::Deserialize;

const DEFAULT_CONFIG_LOCATIONS: [&str; 2] =
    ["./connection-node.toml", "/etc/mrt/connection-node.toml"];

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum NodeMode {
    SelfHosted,
    Managed,
}

impl Default for NodeMode {
    fn default() -> Self {
        Self::SelfHosted
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum StorageKind {
    Sqlite,
    Postgres,
}

impl Default for StorageKind {
    fn default() -> Self {
        Self::Sqlite
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(default)]
pub struct ServerConfig {
    pub listen_addr: String,
    pub mode: NodeMode,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            listen_addr: "0.0.0.0:8443".to_string(),
            mode: NodeMode::SelfHosted,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(default)]
pub struct StorageConfig {
    #[serde(rename = "type")]
    pub kind: StorageKind,
    pub path: String,
    pub url: Option<String>,
}

impl Default for StorageConfig {
    fn default() -> Self {
        Self {
            kind: StorageKind::Sqlite,
            path: "./mrt-node.db".to_string(),
            url: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(default)]
pub struct LogConfig {
    pub level: String,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            level: "info".to_string(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Default)]
#[serde(default)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub storage: StorageConfig,
    pub log: LogConfig,
}

impl AppConfig {
    pub fn load(config_path: Option<&Path>) -> Result<Self> {
        match config_path {
            Some(path) => Self::load_from_path(path),
            None => {
                if let Some(path) = DEFAULT_CONFIG_LOCATIONS
                    .iter()
                    .map(PathBuf::from)
                    .find(|path| path.exists())
                {
                    Self::load_from_path(path)
                } else {
                    Ok(Self::default())
                }
            }
        }
    }

    pub fn load_from_path(path: impl AsRef<Path>) -> Result<Self> {
        let content = fs::read_to_string(path.as_ref())?;
        Ok(toml::from_str(&content)?)
    }
}
