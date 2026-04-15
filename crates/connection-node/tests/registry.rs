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
    assert!(registry
        .get_sender_for_user(user_id, "alice-mac")
        .await
        .is_some());
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

    registry
        .unregister(user_id, "alice-mac")
        .await
        .expect("unregister");

    let devices = registry.list_devices_for_user(user_id).await;
    assert_eq!(devices.len(), 1);
    assert!(!devices[0].is_online);
    assert!(devices[0].last_seen_ms > 0);
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
    assert!(registry
        .get_sender_for_user(alice_id, "bob-phone")
        .await
        .is_none());
    assert!(registry
        .get_sender_for_user(bob_id, "alice-mac")
        .await
        .is_none());
}

#[tokio::test]
async fn same_device_id_is_isolated_across_users_in_db_and_online_map() {
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
                device_id: "shared-device".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Alice Shared".into(),
                agent_version: "1.0.0".into(),
            },
            alice_tx,
        )
        .await
        .expect("register alice");
    registry
        .register(
            DeviceRegister {
                device_id: "shared-device".into(),
                auth_token: "mrt_ak_bob1234567890abcdef".into(),
                device_type: DeviceType::Phone as i32,
                display_name: "Bob Shared".into(),
                agent_version: "1.0.0".into(),
            },
            bob_tx,
        )
        .await
        .expect("register bob");

    let alice_persisted = db
        .list_devices_for_user(alice_id)
        .expect("list alice devices");
    let bob_persisted = db.list_devices_for_user(bob_id).expect("list bob devices");

    assert_eq!(alice_persisted.len(), 1);
    assert_eq!(alice_persisted[0].device_id, "shared-device");
    assert_eq!(
        alice_persisted[0].display_name.as_deref(),
        Some("Alice Shared")
    );
    assert_eq!(bob_persisted.len(), 1);
    assert_eq!(bob_persisted[0].device_id, "shared-device");
    assert_eq!(bob_persisted[0].display_name.as_deref(), Some("Bob Shared"));

    let alice_devices = registry.list_devices_for_user(alice_id).await;
    let bob_devices = registry.list_devices_for_user(bob_id).await;

    assert_eq!(alice_devices.len(), 1);
    assert_eq!(alice_devices[0].device_id, "shared-device");
    assert!(alice_devices[0].is_online);
    assert_eq!(alice_devices[0].display_name, "Alice Shared");
    assert_eq!(bob_devices.len(), 1);
    assert_eq!(bob_devices[0].device_id, "shared-device");
    assert!(bob_devices[0].is_online);
    assert_eq!(bob_devices[0].display_name, "Bob Shared");
}

#[tokio::test]
async fn list_devices_for_user_uses_persisted_state_and_online_enrichment() {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert user");
    let user_id = db.list_users().expect("list users")[0].id;
    db.upsert_device(
        user_id,
        "offline-phone",
        DeviceType::Phone as i32,
        "Offline Phone",
    )
    .expect("insert offline device");
    db.update_device_last_seen(user_id, "offline-phone", 42_000)
        .expect("set last seen");

    let registry = DeviceRegistry::new(Arc::clone(&db));
    let (tx, _rx) = mpsc::channel(4);
    registry
        .register(
            DeviceRegister {
                device_id: "online-mac".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Online Mac".into(),
                agent_version: "1.0.0".into(),
            },
            tx,
        )
        .await
        .expect("register online device");

    let devices = registry.list_devices_for_user(user_id).await;
    assert_eq!(devices.len(), 2);

    let offline = devices
        .iter()
        .find(|device| device.device_id == "offline-phone")
        .expect("offline device");
    assert_eq!(offline.device_type, DeviceType::Phone as i32);
    assert_eq!(offline.display_name, "Offline Phone");
    assert!(!offline.is_online);
    assert_eq!(offline.last_seen_ms, 42_000);

    let online = devices
        .iter()
        .find(|device| device.device_id == "online-mac")
        .expect("online device");
    assert_eq!(online.device_type, DeviceType::Agent as i32);
    assert_eq!(online.display_name, "Online Mac");
    assert!(online.is_online);
    assert_eq!(online.last_seen_ms, 0);
}
