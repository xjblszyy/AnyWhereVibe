use anyhow::bail;
use async_trait::async_trait;
use proto_gen::AgentEvent;
use tokio::sync::broadcast;

use crate::adapter::AgentAdapter;
use crate::codex::{process::CodexProcessManager, rpc::CodexRpcClient};

#[derive(Debug)]
pub struct CodexAppServerAdapter {
    process: CodexProcessManager,
    rpc: Option<CodexRpcClient>,
    event_tx: broadcast::Sender<AgentEvent>,
}

impl CodexAppServerAdapter {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(16);
        Self {
            process: CodexProcessManager::new(),
            rpc: None,
            event_tx,
        }
    }
}

impl Default for CodexAppServerAdapter {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl AgentAdapter for CodexAppServerAdapter {
    fn name(&self) -> &'static str {
        "codex-app-server"
    }

    async fn send_prompt(&self, _session_id: &str, _prompt: &str) -> anyhow::Result<()> {
        let _ = &self.process;
        let _ = &self.rpc;
        bail!("codex app-server adapter is not implemented in the A-slice")
    }

    async fn respond_approval(&self, _approval_id: &str, _approved: bool) -> anyhow::Result<()> {
        bail!("codex app-server adapter is not implemented in the A-slice")
    }

    async fn cancel_task(&self, _session_id: &str) -> anyhow::Result<()> {
        bail!("codex app-server adapter is not implemented in the A-slice")
    }

    async fn get_status(&self, _session_id: &str) -> anyhow::Result<i32> {
        bail!("codex app-server adapter is not implemented in the A-slice")
    }

    fn subscribe(&self) -> broadcast::Receiver<AgentEvent> {
        self.event_tx.subscribe()
    }

    async fn start(&mut self) -> anyhow::Result<()> {
        bail!("codex app-server adapter is not implemented in the A-slice")
    }

    async fn stop(&mut self) -> anyhow::Result<()> {
        bail!("codex app-server adapter is not implemented in the A-slice")
    }
}
