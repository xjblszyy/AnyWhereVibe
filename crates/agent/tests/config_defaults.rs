use std::path::Path;

use agent::config::Config;

#[test]
fn config_defaults_match_task_contract() {
    let config = Config::default();

    assert_eq!(config.server.listen_addr, "0.0.0.0:9876");
    assert_eq!(config.agent.adapter, "codex-app-server");
    assert!(config.agent.auto_fallback);
    assert!(Path::new(&config.storage.sessions_path).ends_with(".mrt/sessions.json"));
}
