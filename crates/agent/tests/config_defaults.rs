use std::path::Path;

use agent::config::Config;

#[test]
fn config_defaults_match_task_contract() {
    let config = Config::default();

    assert_eq!(config.server.listen_addr, "0.0.0.0:9876");
    assert_eq!(config.agent.adapter, "mock");
    assert!(config.agent.auto_fallback);
    assert!(config.connection_node.is_none());
    assert!(Path::new(&config.storage.sessions_path).ends_with(".mrt/sessions.json"));
}

#[test]
fn config_parses_optional_connection_node_section() {
    let config: Config = toml::from_str(
        r#"
            [server]
            listen_addr = "127.0.0.1:9876"

            [agent]
            adapter = "mock"
            auto_fallback = true

            [codex]
            command = "codex"
            args = ["app-server"]

            [storage]
            sessions_path = "/tmp/sessions.json"

            [log]
            level = "debug"

            [connection_node]
            url = "wss://relay.example.com/ws"
            device_id = "ming-macbook"
            display_name = "Ming's MacBook"
            auth_token = "mrt_ak_example1234567890"
        "#,
    )
    .expect("parse config");

    let connection_node = config.connection_node.expect("connection node config");
    assert_eq!(connection_node.url, "wss://relay.example.com/ws");
    assert_eq!(connection_node.device_id, "ming-macbook");
    assert_eq!(connection_node.display_name, "Ming's MacBook");
    assert_eq!(connection_node.auth_token, "mrt_ak_example1234567890");
}
