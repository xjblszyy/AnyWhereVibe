# Agent Transport Abstraction Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete `AGENT-T10` so the agent selects transport from config, supports local mode explicitly, and returns a clear unsupported error for configured Connection Node mode.

**Architecture:** Extend `Config` with an optional `connection_node` section, teach `Transport` to build itself from config, and wire `Daemon` through `Transport::from_config()` instead of hard-coding local mode. Keep remote mode intentionally stubbed, but make the stub reachable and tested as the contract requires.

**Tech Stack:** Rust, Tokio, Serde/TOML, existing `agent` crate tests.

---

### Task 1: Add Config Coverage For Connection Node

**Files:**
- Modify: `crates/agent/src/config.rs`
- Modify: `crates/agent/tests/config_defaults.rs`

- [ ] **Step 1: Write the failing config tests**

Add tests asserting:
- `Config::default().connection_node` is `None`
- TOML with `[connection_node]` parses `url`, `device_id`, `display_name`, and `auth_token`

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p agent config_defaults_match_task_contract`
Expected: FAIL because `Config` does not yet expose `connection_node`

- [ ] **Step 3: Write minimal implementation**

Add:
- `pub connection_node: Option<ConnectionNodeConfig>` to `Config`
- `ConnectionNodeConfig` struct with `url`, `device_id`, `display_name`, `auth_token`
- Default config keeps `connection_node = None`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cargo test -p agent config_defaults_match_task_contract`
Expected: PASS

### Task 2: Implement Transport Selection And Stubbed Remote Contract

**Files:**
- Modify: `crates/agent/src/transport.rs`
- Modify: `crates/agent/src/daemon.rs`
- Create: `crates/agent/tests/transport_config.rs`

- [ ] **Step 1: Write the failing transport tests**

Create tests asserting:
- local config returns `Transport::Local { listen_addr }`
- config with `connection_node` returns `Transport::Remote { ... }`
- calling `listen_addr()` on remote transport fails with the exact unsupported-mode contract
- daemon transport selection uses config rather than hard-coded local listen addr

- [ ] **Step 2: Run tests to verify they fail**

Run: `cargo test -p agent transport_`
Expected: FAIL because `Transport::from_config()` and remote config selection do not exist

- [ ] **Step 3: Write minimal implementation**

Implement:
- `Transport::Remote { node_url, device_id, display_name, auth_token }`
- `Transport::from_config(config: &Config) -> Result<Self>`
- `Daemon::run()` uses `Transport::from_config(&self.config)?`
- Local transport continues to bind via `Server::bind(...)`
- Remote transport path returns the explicit unsupported error before server bind

- [ ] **Step 4: Run targeted tests to verify they pass**

Run: `cargo test -p agent transport_`
Expected: PASS

- [ ] **Step 5: Run full agent test suite**

Run: `cargo test -p agent`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-04-15-agent-transport-abstraction.md crates/agent/src/config.rs crates/agent/src/transport.rs crates/agent/src/daemon.rs crates/agent/tests/config_defaults.rs crates/agent/tests/transport_config.rs
git commit -m "feat: wire agent transport selection from config"
```
