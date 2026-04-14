use agent::session::SessionManager;
use proto_gen::TaskStatus;
use std::fs;
use tempfile::tempdir;

#[test]
fn whitespace_only_sessions_file_is_a_load_error() {
    let temp_dir = tempdir().expect("temp dir");
    let sessions_path = temp_dir.path().join("sessions.json");

    fs::write(&sessions_path, "   \n\t").expect("write whitespace-only sessions file");

    let error = SessionManager::new(&sessions_path).expect_err("whitespace-only json must fail");
    assert!(error.to_string().contains("failed to parse session storage file"));
}

#[test]
fn update_status_returns_result_and_persists_sessions_to_disk() {
    let temp_dir = tempdir().expect("temp dir");
    let sessions_path = temp_dir.path().join("nested").join("sessions.json");

    let mut manager = SessionManager::new(&sessions_path).expect("load manager");

    let session = manager
        .create("Main", "/tmp/project")
        .expect("create session");

    assert_eq!(session.name, "Main");
    assert_eq!(session.working_dir, "/tmp/project");
    assert_eq!(session.status, TaskStatus::Idle as i32);
    assert!(session.created_at_ms > 0);
    assert_eq!(session.created_at_ms, session.last_active_ms);

    manager
        .update_status(&session.id, TaskStatus::Running)
        .expect("update status");

    let reloaded = SessionManager::new(&sessions_path).expect("reload manager");
    let persisted = reloaded
        .get(&session.id)
        .expect("persisted session should exist");

    assert_eq!(persisted.id, session.id);
    assert_eq!(persisted.name, "Main");
    assert_eq!(persisted.working_dir, "/tmp/project");
    assert_eq!(persisted.status, TaskStatus::Running as i32);
    assert_eq!(persisted.created_at_ms, session.created_at_ms);
    assert!(persisted.last_active_ms >= persisted.created_at_ms);

    let sessions = reloaded.list();
    assert_eq!(sessions.len(), 1);

    let listed = &sessions[0];
    assert_eq!(listed.session_id, session.id);
    assert_eq!(listed.name, "Main");
    assert_eq!(listed.working_dir, "/tmp/project");
    assert_eq!(listed.status, TaskStatus::Running as i32);
    assert_eq!(listed.created_at_ms, session.created_at_ms);
    assert_eq!(listed.last_active_ms, persisted.last_active_ms);
}
