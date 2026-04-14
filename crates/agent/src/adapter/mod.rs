mod codex_appserver;
mod codex_cli;
mod mock;

use async_trait::async_trait;
use tokio::sync::broadcast;

pub use codex_appserver::CodexAppServerAdapter;
pub use codex_cli::CodexCliAdapter;
pub use mock::MockAdapter;

#[async_trait]
pub trait AgentAdapter: Send + Sync + 'static {
    fn name(&self) -> &'static str;

    async fn send_prompt(&self, session_id: &str, prompt: &str) -> anyhow::Result<()>;

    async fn respond_approval(&self, approval_id: &str, approved: bool) -> anyhow::Result<()>;

    async fn cancel_task(&self, session_id: &str) -> anyhow::Result<()>;

    async fn get_status(&self, session_id: &str) -> anyhow::Result<i32>;

    fn subscribe(&self) -> broadcast::Receiver<proto_gen::AgentEvent>;

    async fn start(&mut self) -> anyhow::Result<()>;

    async fn stop(&mut self) -> anyhow::Result<()>;
}
