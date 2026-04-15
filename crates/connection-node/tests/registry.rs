use std::sync::Arc;

use connection_node::db::Database;
use connection_node::registry::DeviceRegistry;
use proto_gen::{DeviceRegister, DeviceType};
use tokio::sync::mpsc;

#[tokio::test]
async fn valid_token_register_makes_device_visible_online() {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert user");
    let user_id = db.list_users().expect("list users")[0].id;
    let registry = DeviceRegistry::new(Arc::clone(&db));
    let (tx, _rx) = mpsc::channel(4);

    let ack = registry
        .register(
            DeviceRegister {
                device_id: "alice-mac".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Alice Mac".into(),
                agent_version: "1.0.0".into(),
            },
            tx,
        )
        .await
        .expect("register device");

    assert!(ack.success);
    let devices = registry.list_devices_for_user(user_id).await;
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0].device_id, "alice-mac");
    assert_eq!(devices[0].device_type, DeviceType::Agent as i32);
    assert!(devices[0].is_online);
    assert!(registry.find_device(user_id, "alice-mac").await.is_some());
    assert!(registry.get_sender("alice-mac").await.is_some());
}

#[tokio::test]
async fn invalid_token_register_fails() {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    let registry = DeviceRegistry::new(Arc::clone(&db));
    let (tx, _rx) = mpsc::channel(4);

    let err = registry
        .register(
            DeviceRegister {
                device_id: "bad-device".into(),
                auth_token: "mrt_ak_invalid".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Bad Device".into(),
                agent_version: "1.0.0".into(),
            },
            tx,
        )
        .await
        .expect_err("invalid token should fail");

    assert!(err.to_string().contains("invalid auth token"));
}

#[tokio::test]
async fn unregister_removes_device_from_online_map_and_updates_last_seen() {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert user");
    let user_id = db.list_users().expect("list users")[0].id;
    let registry = DeviceRegistry::new(Arc::clone(&db));
    let (tx, _rx) = mpsc::channel(4);

    registry
        .register(
            DeviceRegister {
                device_id: "alice-mac".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Alice Mac".into(),
                agent_version: "1.0.0".into(),
            },
            tx,
        )
        .await
        .expect("register device");

    registry.unregister("alice-mac").await.expect("unregister");

    assert!(registry.list_devices_for_user(user_id).await.is_empty());
    assert!(registry.find_device(user_id, "alice-mac").await.is_none());

    let persisted = db
        .list_devices_for_user(user_id)
        .expect("list persisted devices");
    assert_eq!(persisted.len(), 1);
    assert_eq!(persisted[0].device_id, "alice-mac");
    assert!(persisted[0].last_seen_ms.unwrap_or(0) > 0);
}

#[tokio::test]
async fn user_isolation_blocks_cross_user_visibility() {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert alice");
    db.insert_user("bob", "mrt_ak_bob1234567890abcdef")
        .expect("insert bob");
    let users = db.list_users().expect("list users");
    let alice_id = users.iter().find(|user| user.name == "alice").unwrap().id;
    let bob_id = users.iter().find(|user| user.name == "bob").unwrap().id;
    let registry = DeviceRegistry::new(Arc::clone(&db));
    let (alice_tx, _alice_rx) = mpsc::channel(4);
    let (bob_tx, _bob_rx) = mpsc::channel(4);

    registry
        .register(
            DeviceRegister {
                device_id: "alice-mac".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Alice Mac".into(),
                agent_version: "1.0.0".into(),
            },
            alice_tx,
        )
        .await
        .expect("register alice");
    registry
        .register(
            DeviceRegister {
                device_id: "bob-phone".into(),
                auth_token: "mrt_ak_bob1234567890abcdef".into(),
                device_type: DeviceType::Phone as i32,
                display_name: "Bob Phone".into(),
                agent_version: "1.0.0".into(),
            },
            bob_tx,
        )
        .await
        .expect("register bob");

    let alice_devices = registry.list_devices_for_user(alice_id).await;
    let bob_devices = registry.list_devices_for_user(bob_id).await;

    assert_eq!(alice_devices.len(), 1);
    assert_eq!(alice_devices[0].device_id, "alice-mac");
    assert_eq!(bob_devices.len(), 1);
    assert_eq!(bob_devices[0].device_id, "bob-phone");
    assert!(registry.find_device(alice_id, "bob-phone").await.is_none());
    assert!(registry.find_device(bob_id, "alice-mac").await.is_none());
}
