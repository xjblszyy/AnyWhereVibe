use anyhow::bail;

#[derive(Debug, Default)]
pub struct CodexProcessManager;

impl CodexProcessManager {
    pub fn new() -> Self {
        Self
    }

    pub async fn start(&mut self) -> anyhow::Result<String> {
        bail!("codex process manager is not implemented in the A-slice")
    }

    pub async fn stop(&mut self) -> anyhow::Result<()> {
        bail!("codex process manager is not implemented in the A-slice")
    }
}
