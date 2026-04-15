use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use proto_gen::{DeviceInfo, DeviceRegister, DeviceRegisterAck, DeviceType};
use tokio::sync::{mpsc, RwLock};

use crate::db::Database;

pub struct DeviceRegistry {
    db: Arc<Database>,
    online: RwLock<HashMap<String, OnlineDevice>>,
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

        let device_id = msg.device_id.clone();
        let online_device = OnlineDevice {
            user_id: user.id,
            device_id: msg.device_id,
            device_type,
            display_name: msg.display_name,
            ws_tx,
            connected_at: Instant::now(),
        };

        self.online.write().await.insert(device_id, online_device);

        Ok(DeviceRegisterAck {
            success: true,
            message: "registered".to_string(),
        })
    }

    pub async fn unregister(&self, device_id: &str) -> Result<()> {
        let removed = self.online.write().await.remove(device_id);
        if removed.is_some() {
            self.db
                .update_device_last_seen(device_id, current_timestamp_ms()?)?;
        }
        Ok(())
    }

    pub async fn list_devices_for_user(&self, user_id: i64) -> Vec<DeviceInfo> {
        self.online
            .read()
            .await
            .values()
            .filter(|device| device.user_id == user_id)
            .map(|device| DeviceInfo {
                device_id: device.device_id.clone(),
                device_type: device.device_type as i32,
                display_name: device.display_name.clone(),
                is_online: true,
                last_seen_ms: 0,
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
            .get(target_device_id)
            .filter(|device| device.user_id == requester_user_id)
            .cloned()
    }

    pub async fn get_sender(&self, device_id: &str) -> Option<mpsc::Sender<Vec<u8>>> {
        self.online
            .read()
            .await
            .get(device_id)
            .map(|device| device.ws_tx.clone())
    }
}

fn current_timestamp_ms() -> Result<u64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis() as u64)
}
