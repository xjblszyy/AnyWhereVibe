use std::sync::Arc;
use std::time::Duration;

use connection_node::db::Database;
use connection_node::registry::DeviceRegistry;
use connection_node::router::SessionRouter;
use proto_gen::{ConnectionType, DeviceRegister, DeviceType};
use tokio::sync::mpsc;
use tokio::time::timeout;

#[tokio::test]
async fn connect_succeeds_for_same_user_phone_and_agent_and_records_session() {
    let (_db, registry, _phone_rx, _agent_rx) = setup_same_user_registry().await;
    let router = SessionRouter::new(registry);

    let ack = router
        .connect("alice-phone", "alice-agent")
        .await
        .expect("connect");

    assert!(ack.success);
    assert_eq!(ack.connection_type, ConnectionType::Relay as i32);
    let session = router
        .session_for_phone("alice-phone")
        .await
        .expect("session");
    assert_eq!(session.phone_device_id, "alice-phone");
    assert_eq!(session.agent_device_id, "alice-agent");
    assert_eq!(session.bytes_forwarded, 0);
}

#[tokio::test]
async fn connect_rejects_cross_user_target() {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert alice");
    db.insert_user("bob", "mrt_ak_bob1234567890abcdef")
        .expect("insert bob");
    let registry = Arc::new(DeviceRegistry::new(Arc::clone(&db)));

    let (alice_tx, _alice_rx) = mpsc::channel(4);
    registry
        .register(
            DeviceRegister {
                device_id: "alice-phone".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Phone as i32,
                display_name: "Alice Phone".into(),
                agent_version: "1.0.0".into(),
            },
            alice_tx,
        )
        .await
        .expect("register alice");

    let (bob_tx, _bob_rx) = mpsc::channel(4);
    registry
        .register(
            DeviceRegister {
                device_id: "bob-agent".into(),
                auth_token: "mrt_ak_bob1234567890abcdef".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Bob Agent".into(),
                agent_version: "1.0.0".into(),
            },
            bob_tx,
        )
        .await
        .expect("register bob");

    let router = SessionRouter::new(registry);
    let err = router
        .connect("alice-phone", "bob-agent")
        .await
        .expect_err("cross-user connect should fail");

    assert!(err.to_string().contains("same user"));
}

#[tokio::test]
async fn route_forwards_bytes_phone_to_agent_and_agent_to_phone() {
    let (_db, registry, mut phone_rx, mut agent_rx) = setup_same_user_registry().await;
    let router = SessionRouter::new(registry);
    router
        .connect("alice-phone", "alice-agent")
        .await
        .expect("connect");

    router
        .route("alice-phone", vec![1, 2, 3, 4])
        .await
        .expect("phone route");
    let to_agent = timeout(Duration::from_secs(1), agent_rx.recv())
        .await
        .expect("agent recv timeout")
        .expect("agent recv");
    assert_eq!(to_agent, vec![1, 2, 3, 4]);

    router
        .route("alice-agent", vec![9, 8, 7])
        .await
        .expect("agent route");
    let to_phone = timeout(Duration::from_secs(1), phone_rx.recv())
        .await
        .expect("phone recv timeout")
        .expect("phone recv");
    assert_eq!(to_phone, vec![9, 8, 7]);
}

#[tokio::test]
async fn disconnect_removes_session() {
    let (_db, registry, _phone_rx, _agent_rx) = setup_same_user_registry().await;
    let router = SessionRouter::new(registry);
    router
        .connect("alice-phone", "alice-agent")
        .await
        .expect("connect");

    router.disconnect("alice-phone").await;

    assert!(router.session_for_phone("alice-phone").await.is_none());
}

#[tokio::test]
async fn bytes_forwarded_increments() {
    let (_db, registry, mut phone_rx, mut agent_rx) = setup_same_user_registry().await;
    let router = SessionRouter::new(registry);
    router
        .connect("alice-phone", "alice-agent")
        .await
        .expect("connect");

    router
        .route("alice-phone", vec![1, 2, 3, 4])
        .await
        .expect("phone route");
    let _ = timeout(Duration::from_secs(1), agent_rx.recv())
        .await
        .expect("agent recv timeout");
    router
        .route("alice-agent", vec![9, 8, 7])
        .await
        .expect("agent route");
    let _ = timeout(Duration::from_secs(1), phone_rx.recv())
        .await
        .expect("phone recv timeout");

    let session = router
        .session_for_phone("alice-phone")
        .await
        .expect("session");
    assert_eq!(session.bytes_forwarded, 7);
}

#[tokio::test]
async fn connect_for_user_rejects_non_phone_requester() {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert user");
    let user_id = db.list_users().expect("list users")[0].id;
    let registry = Arc::new(DeviceRegistry::new(Arc::clone(&db)));
    let (agent_one_tx, _agent_one_rx) = mpsc::channel(4);
    let (agent_two_tx, _agent_two_rx) = mpsc::channel(4);

    registry
        .register(
            DeviceRegister {
                device_id: "alice-agent-1".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Alice Agent 1".into(),
                agent_version: "1.0.0".into(),
            },
            agent_one_tx,
        )
        .await
        .expect("register agent one");
    registry
        .register(
            DeviceRegister {
                device_id: "alice-agent-2".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Alice Agent 2".into(),
                agent_version: "1.0.0".into(),
            },
            agent_two_tx,
        )
        .await
        .expect("register agent two");

    let router = SessionRouter::new(registry);
    let err = router
        .connect_for_user(user_id, "alice-agent-1", "alice-agent-2")
        .await
        .expect_err("agent requester should fail");

    assert!(err.to_string().contains("phone"));
}

async fn setup_same_user_registry() -> (
    Arc<Database>,
    Arc<DeviceRegistry>,
    mpsc::Receiver<Vec<u8>>,
    mpsc::Receiver<Vec<u8>>,
) {
    let db = Arc::new(Database::open_in_memory().expect("open db"));
    db.insert_user("alice", "mrt_ak_alice1234567890abcd")
        .expect("insert user");
    let registry = Arc::new(DeviceRegistry::new(Arc::clone(&db)));

    let (phone_tx, phone_rx) = mpsc::channel(4);
    registry
        .register(
            DeviceRegister {
                device_id: "alice-phone".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Phone as i32,
                display_name: "Alice Phone".into(),
                agent_version: "1.0.0".into(),
            },
            phone_tx,
        )
        .await
        .expect("register phone");

    let (agent_tx, agent_rx) = mpsc::channel(4);
    registry
        .register(
            DeviceRegister {
                device_id: "alice-agent".into(),
                auth_token: "mrt_ak_alice1234567890abcd".into(),
                device_type: DeviceType::Agent as i32,
                display_name: "Alice Agent".into(),
                agent_version: "1.0.0".into(),
            },
            agent_tx,
        )
        .await
        .expect("register agent");

    (db, registry, phone_rx, agent_rx)
}
