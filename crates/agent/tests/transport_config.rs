use std::fs;

use agent::config::{Config, ConnectionNodeConfig};
use agent::transport::Transport;

#[test]
fn transport_from_config_defaults_to_local_listen_addr() {
    let config = Config::default();

    let transport = Transport::from_config(&config).expect("transport");

    assert_eq!(
        transport,
        Transport::Local {
            listen_addr: "0.0.0.0:9876".into(),
        }
    );
}

#[test]
fn transport_from_config_prefers_connection_node_when_present() {
    let mut config = Config::default();
    config.connection_node = Some(ConnectionNodeConfig {
        url: "wss://relay.example.com/ws".into(),
        device_id: "ming-macbook".into(),
        display_name: "Ming's MacBook".into(),
        auth_token: "mrt_ak_example1234567890".into(),
    });

    let transport = Transport::from_config(&config).expect("transport");

    assert_eq!(
        transport,
        Transport::Remote {
            node_url: "wss://relay.example.com/ws".into(),
            device_id: "ming-macbook".into(),
            display_name: "Ming's MacBook".into(),
            auth_token: "mrt_ak_example1234567890".into(),
        }
    );
}

#[test]
fn remote_transport_listen_addr_returns_contract_error() {
    let error = Transport::Remote {
        node_url: "wss://relay.example.com/ws".into(),
        device_id: "ming-macbook".into(),
        display_name: "Ming's MacBook".into(),
        auth_token: "mrt_ak_example1234567890".into(),
    }
    .listen_addr()
    .expect_err("remote transport should not expose local listen addr");

    assert_eq!(
        error.to_string(),
        "connection node transport is not yet supported",
    );
}

#[tokio::test]
async fn remote_transport_uses_loopback_proxy_bind_addr() {
    let dir = tempfile::tempdir().expect("tempdir");
    let config_path = dir.path().join("agent.toml");
    fs::write(
        &config_path,
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
    .expect("write config");

    let config: Config = toml::from_str(&fs::read_to_string(&config_path).expect("read config"))
        .expect("parse config");
    let transport = Transport::from_config(&config).expect("transport");

    assert_eq!(transport.server_bind_addr(), "127.0.0.1:0");
}
