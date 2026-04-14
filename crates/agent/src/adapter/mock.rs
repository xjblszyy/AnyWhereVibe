use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{bail, ensure};
use async_trait::async_trait;
use proto_gen::agent_event::Evt;
use proto_gen::{
    AgentEvent, ApprovalRequest, ApprovalType, CodexOutput, OutputType, TaskStatus,
    TaskStatusUpdate,
};
use tokio::sync::{broadcast, oneshot, Mutex};
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
    next_task_id: AtomicU64,
    session_statuses: Mutex<HashMap<String, i32>>,
    active_tasks: Mutex<HashMap<u64, TaskControl>>,
    pending_approvals: Mutex<HashMap<String, PendingApproval>>,
}

#[derive(Debug)]
struct TaskControl {
    session_id: String,
    cancel_flag: Arc<AtomicBool>,
}

#[derive(Debug)]
struct PendingApproval {
    session_id: String,
    task_id: u64,
    response_tx: oneshot::Sender<bool>,
}

impl MockAdapter {
    pub fn new() -> Self {
        let (event_tx, _) = broadcast::channel(64);
        Self {
            inner: Arc::new(MockAdapterInner {
                event_tx,
                started: AtomicBool::new(false),
                prompt_count: AtomicU32::new(0),
                next_task_id: AtomicU64::new(0),
                session_statuses: Mutex::new(HashMap::new()),
                active_tasks: Mutex::new(HashMap::new()),
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
        let task_id = self.inner.next_task_id.fetch_add(1, Ordering::SeqCst) + 1;
        let inner = Arc::clone(&self.inner);
        let session_id = session_id.to_owned();
        let prompt = prompt.to_owned();
        let cancel_flag = Arc::new(AtomicBool::new(false));

        self.inner
            .register_task(task_id, session_id.clone(), Arc::clone(&cancel_flag))
            .await;

        tokio::spawn(async move {
            inner
                .run_prompt(task_id, prompt_index, session_id, prompt, cancel_flag)
                .await;
        });

        Ok(())
    }

    async fn respond_approval(&self, approval_id: &str, approved: bool) -> anyhow::Result<()> {
        ensure!(
            self.inner.started.load(Ordering::SeqCst),
            "mock adapter is not running"
        );

        let pending_approval = {
            let mut approvals = self.inner.pending_approvals.lock().await;
            approvals.remove(approval_id)
        };

        if let Some(pending_approval) = pending_approval {
            pending_approval
                .response_tx
                .send(approved)
                .map_err(|_| anyhow::anyhow!("mock approval is no longer active"))?;
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

        self.inner.cancel_session_tasks(session_id).await;
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
        let stopped_sessions = self.inner.stop_all_tasks().await;
        for session_id in stopped_sessions {
            self.inner
                .emit_status(&session_id, TaskStatus::Cancelled, "mock task cancelled")
                .await;
            self.inner
                .emit_status(&session_id, TaskStatus::Idle, "mock adapter is idle")
                .await;
        }
        Ok(())
    }
}

impl MockAdapterInner {
    async fn register_task(&self, task_id: u64, session_id: String, cancel_flag: Arc<AtomicBool>) {
        self.active_tasks.lock().await.insert(
            task_id,
            TaskControl {
                session_id,
                cancel_flag,
            },
        );
    }

    async fn run_prompt(
        &self,
        task_id: u64,
        prompt_index: u32,
        session_id: String,
        prompt: String,
        cancel_flag: Arc<AtomicBool>,
    ) {
        if self.should_abort(&cancel_flag) {
            self.finish_task(task_id).await;
            return;
        }

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

        for (index, chunk) in chunks.iter().enumerate() {
            sleep(Duration::from_millis(CHUNK_DELAY_MS)).await;

            if self.should_abort(&cancel_flag) {
                self.finish_task(task_id).await;
                return;
            }

            self.emit_output(&session_id, chunk.clone(), index + 1 == chunks.len())
                .await;

            if approval_after == Some(index + 1) {
                let (response_tx, response_rx) = oneshot::channel();
                let approval_id = Uuid::new_v4().to_string();
                self.pending_approvals.lock().await.insert(
                    approval_id.clone(),
                    PendingApproval {
                        session_id: session_id.clone(),
                        task_id,
                        response_tx,
                    },
                );

                if self.should_abort(&cancel_flag) {
                    self.pending_approvals.lock().await.remove(&approval_id);
                    self.finish_task(task_id).await;
                    return;
                }

                self.emit_status(
                    &session_id,
                    TaskStatus::WaitingApproval,
                    "mock approval required",
                )
                .await;
                self.emit_approval(&session_id, approval_id).await;

                match response_rx.await {
                    Ok(true) => {
                        if self.should_abort(&cancel_flag) {
                            self.finish_task(task_id).await;
                            return;
                        }

                        self.emit_status(
                            &session_id,
                            TaskStatus::Running,
                            "mock approval accepted",
                        )
                        .await;
                    }
                    Ok(false) => {
                        self.emit_status(
                            &session_id,
                            TaskStatus::Cancelled,
                            "mock approval rejected",
                        )
                        .await;
                        self.emit_status(&session_id, TaskStatus::Idle, "mock adapter is idle")
                            .await;
                        self.finish_task(task_id).await;
                        return;
                    }
                    Err(_) => {
                        self.finish_task(task_id).await;
                        return;
                    }
                }
            }
        }

        if self.should_abort(&cancel_flag) {
            self.finish_task(task_id).await;
            return;
        }

        self.emit_status(&session_id, TaskStatus::Completed, "mock task completed")
            .await;
        self.emit_status(&session_id, TaskStatus::Idle, "mock adapter is idle")
            .await;
        self.finish_task(task_id).await;
    }

    fn should_abort(&self, cancel_flag: &AtomicBool) -> bool {
        !self.started.load(Ordering::SeqCst) || cancel_flag.load(Ordering::SeqCst)
    }

    async fn finish_task(&self, task_id: u64) {
        self.active_tasks.lock().await.remove(&task_id);
    }

    async fn cancel_session_tasks(&self, session_id: &str) {
        let task_ids = {
            let mut active_tasks = self.active_tasks.lock().await;
            let task_ids: Vec<u64> = active_tasks
                .iter()
                .filter_map(|(task_id, task)| {
                    if task.session_id == session_id {
                        task.cancel_flag.store(true, Ordering::SeqCst);
                        Some(*task_id)
                    } else {
                        None
                    }
                })
                .collect();

            for task_id in &task_ids {
                active_tasks.remove(task_id);
            }

            task_ids
        };

        let mut pending_approvals = self.pending_approvals.lock().await;
        pending_approvals.retain(|_, approval| {
            approval.session_id != session_id && !task_ids.contains(&approval.task_id)
        });
    }

    async fn stop_all_tasks(&self) -> Vec<String> {
        let mut active_tasks = self.active_tasks.lock().await;
        let mut stopped_sessions = HashSet::new();
        for task in active_tasks.values() {
            task.cancel_flag.store(true, Ordering::SeqCst);
            stopped_sessions.insert(task.session_id.clone());
        }
        active_tasks.clear();
        drop(active_tasks);

        self.pending_approvals.lock().await.clear();
        stopped_sessions.into_iter().collect()
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
