use anyhow::bail;

#[derive(Debug, Default, Clone)]
pub struct CodexRpcClient;

impl CodexRpcClient {
    pub async fn connect(_url: &str) -> anyhow::Result<Self> {
        bail!("codex rpc client is not implemented in the A-slice")
    }

    pub async fn send_prompt(&self, _session_id: &str, _prompt: &str) -> anyhow::Result<()> {
        bail!("codex rpc client is not implemented in the A-slice")
    }

    pub async fn respond_approval(
        &self,
        _approval_id: &str,
        _approved: bool,
    ) -> anyhow::Result<()> {
        bail!("codex rpc client is not implemented in the A-slice")
    }

    pub async fn cancel_task(&self, _session_id: &str) -> anyhow::Result<()> {
        bail!("codex rpc client is not implemented in the A-slice")
    }

    pub async fn get_status(&self, _session_id: &str) -> anyhow::Result<i32> {
        bail!("codex rpc client is not implemented in the A-slice")
    }

    pub async fn close(&mut self) -> anyhow::Result<()> {
        bail!("codex rpc client is not implemented in the A-slice")
    }
}
