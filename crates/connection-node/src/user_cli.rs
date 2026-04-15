use anyhow::Result;
use rand::RngCore;

use crate::db::{Database, UserRecord};

pub fn add_user(db: &Database, name: &str) -> Result<String> {
    let token = generate_token();
    db.insert_user(name, &token)?;
    Ok(token)
}

pub fn list_users(db: &Database) -> Result<Vec<UserRecord>> {
    db.list_users()
}

pub fn revoke_user(db: &Database, name: &str) -> Result<()> {
    db.revoke_user(name)
}

pub fn reset_user(db: &Database, name: &str) -> Result<String> {
    let token = generate_token();
    db.reset_user_token(name, &token)?;
    Ok(token)
}

pub fn render_users(users: &[UserRecord]) -> String {
    if users.is_empty() {
        return "No users found.".to_string();
    }

    users
        .iter()
        .map(|user| {
            format!(
                "{:<20} {:<50} {}",
                user.name,
                user.token,
                if user.active { "active" } else { "revoked" }
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn generate_token() -> String {
    format!("mrt_ak_{}", generate_random_hex(24))
}

fn generate_random_hex(len: usize) -> String {
    let mut bytes = vec![0_u8; len / 2];
    rand::thread_rng().fill_bytes(&mut bytes);

    let mut output = String::with_capacity(len);
    for byte in bytes {
        output.push(nibble_to_hex(byte >> 4));
        output.push(nibble_to_hex(byte & 0x0f));
    }
    output
}

fn nibble_to_hex(value: u8) -> char {
    match value {
        0..=9 => (b'0' + value) as char,
        10..=15 => (b'a' + (value - 10)) as char,
        _ => unreachable!("nibble outside hexadecimal range"),
    }
}
