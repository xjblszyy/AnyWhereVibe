use anyhow::{anyhow, Result};
use tokio::sync::mpsc;

pub struct RelayEngine;

impl RelayEngine {
    pub async fn forward(target: mpsc::Sender<Vec<u8>>, frame: Vec<u8>) -> Result<()> {
        target
            .send(frame)
            .await
            .map_err(|_| anyhow!("target device channel closed"))
    }
}
