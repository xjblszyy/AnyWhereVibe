use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{bail, ensure};
use async_trait::async_trait;
use proto_gen::agent_event::Evt;
use proto_gen::{
    AgentEvent, ApprovalRequest, ApprovalType, CodexOutput, OutputType, TaskStatus,
    TaskStatusUpdate,
};
use tokio::sync::{broadcast, Mutex};
use tokio::time::sleep;
use uuid::Uuid;

use crate::adapter::AgentAdapter;

const CHUNK_DELAY_MS: u64 = 25;
const CHUNK_SIZE: usize = 10;

#[derive(Debug, Clone)]
pub struct MockAdapter {
    inner: Arc<MockAdapterInner>,
}

#[derive(Debug)]
struct MockAdapterInner {
    event_tx: broadcast::Sender<AgentEvent>,
    started: AtomicBool,
    prompt_count: AtomicU32,
    session_statuses: Mutex<HashMap<String, i32>>,
    pending_approvals: Mutex<HashMap<String, String>>,
}

impl MockAdapter {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(64);
        Self {
            inner: Arc::new(MockAdapterInner {
                event_tx,
                started: AtomicBool::new(false),
                prompt_count: AtomicU32::new(0),
                session_statuses: Mutex::new(HashMap::new()),
                pending_approvals: Mutex::new(HashMap::new()),
            }),
        }
    }
}

impl Default for MockAdapter {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl AgentAdapter for MockAdapter {
    fn name(&self) -> &'static str {
        "mock"
    }

    async fn send_prompt(&self, session_id: &str, prompt: &str) -> anyhow::Result<()> {
        ensure!(
            self.inner.started.load(Ordering::SeqCst),
            "mock adapter is not running"
        );

        let prompt_index = self.inner.prompt_count.fetch_add(1, Ordering::SeqCst) + 1;
        let inner = Arc::clone(&self.inner);
        let session_id = session_id.to_owned();
        let prompt = prompt.to_owned();

        tokio::spawn(async move {
            inner.run_prompt(prompt_index, session_id, prompt).await;
        });

        Ok(())
    }

    async fn respond_approval(&self, approval_id: &str, approved: bool) -> anyhow::Result<()> {
        ensure!(
            self.inner.started.load(Ordering::SeqCst),
            "mock adapter is not running"
        );

        let session_id = {
            let mut approvals = self.inner.pending_approvals.lock().await;
            approvals.remove(approval_id)
        };

        if let Some(session_id) = session_id {
            let summary = if approved {
                "mock approval accepted"
            } else {
                "mock approval rejected"
            };
            self.inner
                .emit_status(&session_id, TaskStatus::Running, summary)
                .await;
            Ok(())
        } else {
            bail!("unknown mock approval id '{approval_id}'")
        }
    }

    async fn cancel_task(&self, session_id: &str) -> anyhow::Result<()> {
        ensure!(
            self.inner.started.load(Ordering::SeqCst),
            "mock adapter is not running"
        );

        self.inner
            .emit_status(session_id, TaskStatus::Cancelled, "mock task cancelled")
            .await;
        self.inner
            .emit_status(session_id, TaskStatus::Idle, "mock adapter is idle")
            .await;
        Ok(())
    }

    async fn get_status(&self, session_id: &str) -> anyhow::Result<i32> {
        let statuses = self.inner.session_statuses.lock().await;
        Ok(statuses
            .get(session_id)
            .copied()
            .unwrap_or(TaskStatus::Idle as i32))
    }

    fn subscribe(&self) -> broadcast::Receiver<AgentEvent> {
        self.inner.event_tx.subscribe()
    }

    async fn start(&mut self) -> anyhow::Result<()> {
        self.inner.started.store(true, Ordering::SeqCst);
        Ok(())
    }

    async fn stop(&mut self) -> anyhow::Result<()> {
        self.inner.started.store(false, Ordering::SeqCst);
        self.inner.session_statuses.lock().await.clear();
        self.inner.pending_approvals.lock().await.clear();
        Ok(())
    }
}

impl MockAdapterInner {
    async fn run_prompt(&self, prompt_index: u32, session_id: String, prompt: String) {
        self.emit_status(&session_id, TaskStatus::Running, "mock task started")
            .await;

        let response =
            format!("Mock adapter received \"{prompt}\" and is streaming a response in chunks.");
        let chunks = split_chunks(&response, CHUNK_SIZE);
        let approval_after = if prompt_index % 3 == 0 {
            Some(2usize)
        } else {
            None
        };
        let mut emitted_approval_id = None;

        for (index, chunk) in chunks.iter().enumerate() {
            sleep(Duration::from_millis(CHUNK_DELAY_MS)).await;
            self.emit_output(&session_id, chunk.clone(), index + 1 == chunks.len())
                .await;

            if approval_after == Some(index + 1) {
                let approval_id = Uuid::new_v4().to_string();
                self.pending_approvals
                    .lock()
                    .await
                    .insert(approval_id.clone(), session_id.clone());
                emitted_approval_id = Some(approval_id.clone());
                self.emit_status(
                    &session_id,
                    TaskStatus::WaitingApproval,
                    "mock approval required",
                )
                .await;
                self.emit_approval(&session_id, approval_id).await;
            }
        }

        if let Some(approval_id) = emitted_approval_id {
            self.pending_approvals.lock().await.remove(&approval_id);
        }

        self.emit_status(&session_id, TaskStatus::Completed, "mock task completed")
            .await;
        self.emit_status(&session_id, TaskStatus::Idle, "mock adapter is idle")
            .await;
    }

    async fn emit_status(&self, session_id: &str, status: TaskStatus, summary: &str) {
        self.session_statuses
            .lock()
            .await
            .insert(session_id.to_owned(), status as i32);

        let _ = self.event_tx.send(AgentEvent {
            evt: Some(Evt::StatusUpdate(TaskStatusUpdate {
                session_id: session_id.to_owned(),
                status: status as i32,
                summary: summary.to_owned(),
            })),
        });
    }

    async fn emit_output(&self, session_id: &str, content: String, is_complete: bool) {
        let _ = self.event_tx.send(AgentEvent {
            evt: Some(Evt::CodexOutput(CodexOutput {
                session_id: session_id.to_owned(),
                content,
                is_complete,
                output_type: OutputType::AssistantText as i32,
            })),
        });
    }

    async fn emit_approval(&self, session_id: &str, approval_id: String) {
        let _ = self.event_tx.send(AgentEvent {
            evt: Some(Evt::ApprovalRequest(ApprovalRequest {
                approval_id,
                session_id: session_id.to_owned(),
                description: "Mock adapter requests approval to write a file".to_owned(),
                command: "cat > src/main.rs <<'EOF'\nfn main() {}\nEOF".to_owned(),
                approval_type: ApprovalType::FileWrite as i32,
            })),
        });
    }
}

fn split_chunks(content: &str, chunk_size: usize) -> Vec<String> {
    let chars: Vec<char> = content.chars().collect();
    chars
        .chunks(chunk_size)
        .map(|chunk| chunk.iter().collect())
        .collect()
}
