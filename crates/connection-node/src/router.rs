use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

use anyhow::{anyhow, Result};
use proto_gen::{ConnectToDeviceAck, ConnectionType, DeviceType};
use tokio::sync::RwLock;

use crate::registry::DeviceRegistry;
use crate::relay::RelayEngine;

pub struct SessionRouter {
    registry: Arc<DeviceRegistry>,
    sessions: RwLock<HashMap<SessionKey, RelaySession>>,
}

struct RelaySession {
    phone_device_id: String,
    agent_device_id: String,
    user_id: i64,
    created_at: Instant,
    bytes_forwarded: AtomicU64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SessionSnapshot {
    pub phone_device_id: String,
    pub agent_device_id: String,
    pub user_id: i64,
    pub bytes_forwarded: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct SessionKey {
    user_id: i64,
    phone_device_id: String,
}

impl SessionRouter {
    pub fn new(registry: Arc<DeviceRegistry>) -> Self {
        Self {
            registry,
            sessions: RwLock::new(HashMap::new()),
        }
    }

    pub async fn connect(
        &self,
        phone_id: &str,
        target_agent_id: &str,
    ) -> Result<ConnectToDeviceAck> {
        let phone = self.registry.find_unique_device(phone_id).await?;
        self.connect_for_user(phone.user_id, phone_id, target_agent_id)
            .await
    }

    pub async fn connect_for_user(
        &self,
        requester_user_id: i64,
        phone_id: &str,
        target_agent_id: &str,
    ) -> Result<ConnectToDeviceAck> {
        let phone = self
            .registry
            .find_device(requester_user_id, phone_id)
            .await
            .ok_or_else(|| anyhow!("phone device '{phone_id}' is not online"))?;
        let agent = self
            .registry
            .find_device(requester_user_id, target_agent_id)
            .await
            .ok_or_else(|| anyhow!("target device must belong to the same user and be online"))?;

        if agent.device_type != DeviceType::Agent {
            return Err(anyhow!("target device must be an online agent"));
        }

        let session = RelaySession {
            phone_device_id: phone.device_id.clone(),
            agent_device_id: agent.device_id.clone(),
            user_id: phone.user_id,
            created_at: Instant::now(),
            bytes_forwarded: AtomicU64::new(0),
        };

        self.sessions.write().await.insert(
            SessionKey::new(requester_user_id, &phone.device_id),
            session,
        );

        Ok(ConnectToDeviceAck {
            success: true,
            message: "connected".to_string(),
            connection_type: ConnectionType::Relay as i32,
        })
    }

    pub async fn disconnect(&self, phone_id: &str) {
        self.sessions
            .write()
            .await
            .retain(|_, session| session.phone_device_id != phone_id);
    }

    pub async fn disconnect_device(&self, user_id: i64, device_id: &str) {
        self.sessions.write().await.retain(|_, session| {
            !(session.user_id == user_id
                && (session.phone_device_id == device_id || session.agent_device_id == device_id))
        });
    }

    pub async fn route(&self, from_device_id: &str, frame: Vec<u8>) -> Result<()> {
        let from_device = self.registry.find_unique_device(from_device_id).await?;
        self.route_for_user(from_device.user_id, from_device_id, frame)
            .await
    }

    pub async fn route_for_user(
        &self,
        user_id: i64,
        from_device_id: &str,
        frame: Vec<u8>,
    ) -> Result<()> {
        let frame_len = frame.len() as u64;

        let (target_device_id, user_id, phone_key) = {
            let sessions = self.sessions.read().await;

            if let Some(session) = sessions.get(&SessionKey::new(user_id, from_device_id)) {
                (
                    session.agent_device_id.clone(),
                    session.user_id,
                    SessionKey::new(session.user_id, &session.phone_device_id),
                )
            } else if let Some(session) = sessions.values().find(|session| {
                session.user_id == user_id && session.agent_device_id == from_device_id
            }) {
                (
                    session.phone_device_id.clone(),
                    session.user_id,
                    SessionKey::new(session.user_id, &session.phone_device_id),
                )
            } else {
                return Err(anyhow!(
                    "no active relay session for device '{from_device_id}'"
                ));
            }
        };

        let sender = self
            .registry
            .get_sender_for_user(user_id, &target_device_id)
            .await
            .ok_or_else(|| anyhow!("target device '{target_device_id}' is not online"))?;

        RelayEngine::forward(sender, frame).await?;

        if let Some(session) = self.sessions.read().await.get(&phone_key) {
            session
                .bytes_forwarded
                .fetch_add(frame_len, Ordering::Relaxed);
        }

        Ok(())
    }

    pub async fn session_for_phone(&self, phone_id: &str) -> Option<SessionSnapshot> {
        self.sessions
            .read()
            .await
            .values()
            .find(|session| session.phone_device_id == phone_id)
            .map(|session| {
                let _ = session.created_at;
                SessionSnapshot {
                    phone_device_id: session.phone_device_id.clone(),
                    agent_device_id: session.agent_device_id.clone(),
                    user_id: session.user_id,
                    bytes_forwarded: session.bytes_forwarded.load(Ordering::Relaxed),
                }
            })
    }
}

impl SessionKey {
    fn new(user_id: i64, phone_device_id: &str) -> Self {
        Self {
            user_id,
            phone_device_id: phone_device_id.to_string(),
        }
    }
}
