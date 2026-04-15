use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use proto_gen::{DeviceInfo, DeviceRegister, DeviceRegisterAck, DeviceType};
use tokio::sync::{mpsc, RwLock};

use crate::db::Database;

pub struct DeviceRegistry {
    db: Arc<Database>,
    online: RwLock<HashMap<DeviceKey, OnlineDevice>>,
}

#[derive(Clone, Debug)]
pub struct OnlineDevice {
    pub user_id: i64,
    pub device_id: String,
    pub device_type: DeviceType,
    pub display_name: String,
    pub ws_tx: mpsc::Sender<Vec<u8>>,
    pub connected_at: Instant,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct DeviceKey {
    user_id: i64,
    device_id: String,
}

impl DeviceRegistry {
    pub fn new(db: Arc<Database>) -> Self {
        Self {
            db,
            online: RwLock::new(HashMap::new()),
        }
    }

    pub async fn register(
        &self,
        msg: DeviceRegister,
        ws_tx: mpsc::Sender<Vec<u8>>,
    ) -> Result<DeviceRegisterAck> {
        let user = self
            .db
            .find_active_user_by_token(&msg.auth_token)?
            .ok_or_else(|| anyhow!("invalid auth token"))?;
        let device_type =
            DeviceType::try_from(msg.device_type).map_err(|_| anyhow!("invalid device type"))?;

        self.db
            .upsert_device(user.id, &msg.device_id, msg.device_type, &msg.display_name)?;

        let device_key = DeviceKey::new(user.id, &msg.device_id);
        let online_device = OnlineDevice {
            user_id: user.id,
            device_id: msg.device_id,
            device_type,
            display_name: msg.display_name,
            ws_tx,
            connected_at: Instant::now(),
        };

        self.online.write().await.insert(device_key, online_device);

        Ok(DeviceRegisterAck {
            success: true,
            message: "registered".to_string(),
        })
    }

    pub fn active_user_id_for_token(&self, token: &str) -> Result<Option<i64>> {
        Ok(self
            .db
            .find_active_user_by_token(token)?
            .map(|user| user.id))
    }

    pub async fn unregister(&self, user_id: i64, device_id: &str) -> Result<()> {
        let removed = self
            .online
            .write()
            .await
            .remove(&DeviceKey::new(user_id, device_id));
        if removed.is_some() {
            self.db
                .update_device_last_seen(user_id, device_id, current_timestamp_ms()?)?;
        }
        Ok(())
    }

    pub async fn list_devices_for_user(&self, user_id: i64) -> Vec<DeviceInfo> {
        let persisted = match self.db.list_devices_for_user(user_id) {
            Ok(devices) => devices,
            Err(_) => return Vec::new(),
        };
        let online = self.online.read().await;

        persisted
            .into_iter()
            .map(|device| {
                let key = DeviceKey::new(device.user_id, &device.device_id);
                let online_device = online.get(&key);

                DeviceInfo {
                    device_id: device.device_id,
                    device_type: online_device
                        .map(|device| device.device_type as i32)
                        .unwrap_or(device.device_type),
                    display_name: online_device
                        .map(|device| device.display_name.clone())
                        .or(device.display_name)
                        .unwrap_or_default(),
                    is_online: online_device.is_some(),
                    last_seen_ms: device.last_seen_ms.unwrap_or(0),
                }
            })
            .collect()
    }

    pub async fn find_device(
        &self,
        requester_user_id: i64,
        target_device_id: &str,
    ) -> Option<OnlineDevice> {
        self.online
            .read()
            .await
            .get(&DeviceKey::new(requester_user_id, target_device_id))
            .cloned()
    }

    pub async fn find_unique_device(&self, device_id: &str) -> Result<OnlineDevice> {
        let online = self.online.read().await;
        let mut matches = online
            .values()
            .filter(|device| device.device_id == device_id)
            .cloned();

        let first = matches
            .next()
            .ok_or_else(|| anyhow!("device '{device_id}' is not online"))?;

        if matches.next().is_some() {
            return Err(anyhow!("device '{device_id}' is ambiguous across users"));
        }

        Ok(first)
    }

    pub async fn get_sender_for_user(
        &self,
        requester_user_id: i64,
        device_id: &str,
    ) -> Option<mpsc::Sender<Vec<u8>>> {
        self.online
            .read()
            .await
            .get(&DeviceKey::new(requester_user_id, device_id))
            .map(|device| device.ws_tx.clone())
    }
}

fn current_timestamp_ms() -> Result<u64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis() as u64)
}

impl DeviceKey {
    fn new(user_id: i64, device_id: &str) -> Self {
        Self {
            user_id,
            device_id: device_id.to_string(),
        }
    }
}
