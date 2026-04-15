use connection_node::db::Database;
use connection_node::user_cli::{add_user, list_users, reset_user, revoke_user};

#[test]
fn add_user_returns_token_with_prefix_and_persists() {
    let db = Database::open_in_memory().expect("open db");

    let token = add_user(&db, "ming").expect("add user");

    assert!(token.starts_with("mrt_ak_"));
    assert_eq!(token.len(), 31);

    let users = db.list_users().expect("list users");
    assert_eq!(users.len(), 1);
    assert_eq!(users[0].name, "ming");
    assert_eq!(users[0].token, token);
    assert!(users[0].active);
}

#[test]
fn list_users_returns_created_users() {
    let db = Database::open_in_memory().expect("open db");
    add_user(&db, "ming").expect("add ming");
    add_user(&db, "lina").expect("add lina");

    let users = list_users(&db).expect("list users");
    let names: Vec<_> = users.into_iter().map(|user| user.name).collect();

    assert_eq!(names, vec!["lina".to_string(), "ming".to_string()]);
}

#[test]
fn revoke_and_reset_update_state_and_token() {
    let db = Database::open_in_memory().expect("open db");
    let original = add_user(&db, "ming").expect("add user");

    revoke_user(&db, "ming").expect("revoke user");
    let revoked = db.list_users().expect("list users");
    assert_eq!(revoked.len(), 1);
    assert!(!revoked[0].active);
    assert_eq!(revoked[0].token, original);

    let refreshed = reset_user(&db, "ming").expect("reset user");
    assert_ne!(refreshed, original);
    assert!(refreshed.starts_with("mrt_ak_"));

    let users = db.list_users().expect("list users");
    assert_eq!(users.len(), 1);
    assert!(users[0].active);
    assert_eq!(users[0].token, refreshed);
}
