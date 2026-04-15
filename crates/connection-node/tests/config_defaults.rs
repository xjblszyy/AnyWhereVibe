use std::fs;

use connection_node::config::{AppConfig, NodeMode, StorageKind};
use tempfile::tempdir;

#[test]
fn defaults_use_self_hosted_sqlite_storage() {
    let config = AppConfig::default();

    assert_eq!(config.server.mode, NodeMode::SelfHosted);
    assert_eq!(config.server.listen_addr, "0.0.0.0:8443");
    assert_eq!(config.storage.kind, StorageKind::Sqlite);
    assert_eq!(config.storage.path, "./mrt-node.db");
    assert_eq!(config.log.level, "info");
}

#[test]
fn load_from_toml_overrides_defaults() {
    let dir = tempdir().expect("tempdir");
    let config_path = dir.path().join("connection-node.toml");

    fs::write(
        &config_path,
        r#"
[server]
listen_addr = "127.0.0.1:9443"
mode = "self-hosted"

[storage]
type = "sqlite"
path = "/tmp/custom-node.db"

[log]
level = "debug"
"#,
    )
    .expect("write config");

    let config = AppConfig::load_from_path(&config_path).expect("load config");

    assert_eq!(config.server.listen_addr, "127.0.0.1:9443");
    assert_eq!(config.server.mode, NodeMode::SelfHosted);
    assert_eq!(config.storage.kind, StorageKind::Sqlite);
    assert_eq!(config.storage.path, "/tmp/custom-node.db");
    assert_eq!(config.log.level, "debug");
}
