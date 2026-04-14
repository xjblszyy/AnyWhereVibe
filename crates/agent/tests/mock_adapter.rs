use agent::adapter::{AgentAdapter, MockAdapter};
use proto_gen::agent_event::Evt;
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
