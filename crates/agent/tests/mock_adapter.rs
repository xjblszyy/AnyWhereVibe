use agent::adapter::{AgentAdapter, MockAdapter};
use proto_gen::agent_event::Evt;
use proto_gen::TaskStatus;
use tokio::time::{timeout, Duration};

#[tokio::test]
async fn mock_adapter_streams_output_and_requests_approval_every_third_prompt() {
    let mut adapter = MockAdapter::new();
    adapter.start().await.unwrap();
    let mut rx = adapter.subscribe();

    adapter.send_prompt("session-1", "first").await.unwrap();
    adapter.send_prompt("session-1", "second").await.unwrap();
    adapter.send_prompt("session-1", "third").await.unwrap();

    let mut saw_output = false;
    let mut saw_approval = false;
    for _ in 0..20 {
        let event = timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .unwrap();
        match event.evt {
            Some(Evt::CodexOutput(_)) => saw_output = true,
            Some(Evt::ApprovalRequest(_)) => saw_approval = true,
            _ => {}
        }
        if saw_output && saw_approval {
            break;
        }
    }

    assert!(saw_output);
    assert!(saw_approval);
}

#[tokio::test]
async fn approval_response_resumes_paused_prompt_lifecycle_and_completes() {
    let mut adapter = MockAdapter::new();
    adapter.start().await.unwrap();
    let mut rx = adapter.subscribe();

    adapter.send_prompt("warmup-1", "first").await.unwrap();
    adapter.send_prompt("warmup-2", "second").await.unwrap();
    adapter
        .send_prompt("session-approval", "third")
        .await
        .unwrap();

    let mut approval_id = None;
    let mut approval_seen = false;
    for _ in 0..40 {
        let event = timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .unwrap();
        match event.evt {
            Some(Evt::ApprovalRequest(request)) if request.session_id == "session-approval" => {
                approval_id = Some(request.approval_id);
                approval_seen = true;
                break;
            }
            _ => {}
        }
    }

    assert!(approval_seen, "expected approval request for paused prompt");

    let no_completion_during_pause = timeout(Duration::from_millis(250), async {
        loop {
            let event = rx.recv().await.unwrap();
            match event.evt {
                Some(Evt::StatusUpdate(update))
                    if update.session_id == "session-approval"
                        && update.status == TaskStatus::Completed as i32 =>
                {
                    panic!("prompt completed before approval response")
                }
                Some(Evt::StatusUpdate(update))
                    if update.session_id == "session-approval"
                        && update.status == TaskStatus::Idle as i32 =>
                {
                    panic!("prompt returned idle before approval response")
                }
                _ => {}
            }
        }
    })
    .await;
    assert!(
        no_completion_during_pause.is_err(),
        "paused prompt should not complete before approval response"
    );

    adapter
        .respond_approval(&approval_id.unwrap(), true)
        .await
        .unwrap();

    let mut saw_completed = false;
    let mut saw_idle = false;
    for _ in 0..40 {
        let event = timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .unwrap();
        match event.evt {
            Some(Evt::StatusUpdate(update))
                if update.session_id == "session-approval"
                    && update.status == TaskStatus::Completed as i32 =>
            {
                saw_completed = true;
            }
            Some(Evt::StatusUpdate(update))
                if update.session_id == "session-approval"
                    && update.status == TaskStatus::Idle as i32 =>
            {
                saw_idle = true;
                if saw_completed {
                    break;
                }
            }
            _ => {}
        }
    }

    assert!(saw_completed, "expected prompt to complete after approval");
    assert!(saw_idle, "expected prompt to return to idle after approval");
}

#[tokio::test]
async fn cancel_task_prevents_in_flight_task_from_later_reporting_completion() {
    let mut adapter = MockAdapter::new();
    adapter.start().await.unwrap();
    let mut rx = adapter.subscribe();

    adapter
        .send_prompt("session-cancel", "cancel me")
        .await
        .unwrap();

    let mut saw_output = false;
    for _ in 0..20 {
        let event = timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .unwrap();
        match event.evt {
            Some(Evt::CodexOutput(output)) if output.session_id == "session-cancel" => {
                saw_output = true;
                break;
            }
            _ => {}
        }
    }

    assert!(saw_output, "expected in-flight output before cancellation");

    adapter.cancel_task("session-cancel").await.unwrap();

    let mut saw_cancelled = false;
    let mut saw_idle = false;
    for _ in 0..20 {
        let event = timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .unwrap();
        match event.evt {
            Some(Evt::StatusUpdate(update))
                if update.session_id == "session-cancel"
                    && update.status == TaskStatus::Cancelled as i32 =>
            {
                saw_cancelled = true;
            }
            Some(Evt::StatusUpdate(update))
                if update.session_id == "session-cancel"
                    && update.status == TaskStatus::Idle as i32 =>
            {
                saw_idle = true;
                if saw_cancelled {
                    break;
                }
            }
            _ => {}
        }
    }

    assert!(saw_cancelled, "expected cancelled status");
    assert!(saw_idle, "expected idle status after cancellation");

    let no_completion_after_cancel = timeout(Duration::from_millis(300), async {
        loop {
            let event = rx.recv().await.unwrap();
            match event.evt {
                Some(Evt::StatusUpdate(update))
                    if update.session_id == "session-cancel"
                        && update.status == TaskStatus::Completed as i32 =>
                {
                    panic!("cancelled prompt later reported completion")
                }
                Some(Evt::CodexOutput(output)) if output.session_id == "session-cancel" => {
                    panic!("cancelled prompt leaked later output")
                }
                _ => {}
            }
        }
    })
    .await;
    assert!(
        no_completion_after_cancel.is_err(),
        "cancelled prompt should not emit more output or completion"
    );
}
