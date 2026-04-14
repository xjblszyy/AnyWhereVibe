use std::time::Duration;

use agent::session::SessionManager;
use tempfile::tempdir;
use tokio::time::sleep;

#[tokio::test]
async fn session_persistence_and_timestamps_follow_contract() {
    let temp_dir = tempdir().expect("temp dir");
    let sessions_path = temp_dir.path().join("nested").join("sessions.json");

    let mut manager = SessionManager::load(&sessions_path)
        .await
        .expect("load manager");

    let session = manager
        .upsert_session("session-1".into(), "device-a".into())
        .await
        .expect("create session");

    assert_eq!(session.id, "session-1");
    assert_eq!(session.device_id, "device-a");
    assert!(session.created_at_ms > 0);
    assert_eq!(session.created_at_ms, session.last_active_ms);

    sleep(Duration::from_millis(2)).await;

    let updated = manager
        .upsert_session("session-1".into(), "device-a".into())
        .await
        .expect("update session");

    assert_eq!(updated.created_at_ms, session.created_at_ms);
    assert!(updated.last_active_ms >= updated.created_at_ms);
    assert!(updated.last_active_ms > session.last_active_ms);

    let reloaded = SessionManager::load(&sessions_path)
        .await
        .expect("reload manager");
    let persisted = reloaded
        .get("session-1")
        .expect("persisted session should exist");

    assert_eq!(persisted.id, "session-1");
    assert_eq!(persisted.device_id, "device-a");
    assert_eq!(persisted.created_at_ms, session.created_at_ms);
    assert_eq!(persisted.last_active_ms, updated.last_active_ms);
}
