use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{bail, Context, Result};
use clap::Parser;
use tokio::sync::{oneshot, Mutex};
use tokio::time::{sleep, Duration};
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

use crate::adapter::{AgentAdapter, CodexAppServerAdapter, CodexCliAdapter, MockAdapter};
use crate::config::Config;
use crate::server::Server;
use crate::session::SessionManager;
use crate::transport::{
    bridge_remote_socket_to_local_server, connect_and_register_remote, Transport,
};

#[derive(Debug, Clone, Parser)]
pub struct Cli {
    #[arg(long)]
    pub mock: bool,

    #[arg(long)]
    pub config: Option<PathBuf>,

    #[arg(long)]
    pub listen: Option<String>,

    #[arg(long = "log-level")]
    pub log_level: Option<String>,
}

pub struct Daemon {
    pub config: Config,
}

impl Daemon {
    pub async fn run(self) -> Result<()> {
        init_tracing(&self.config.log.level);

        let transport = Transport::from_config(&self.config)?;
        let listen_addr = transport.server_bind_addr().to_owned();

        let mut adapter = create_adapter(&self.config)?;
        adapter.start().await?;
        let adapter: Arc<dyn AgentAdapter> = Arc::from(adapter);

        let sessions = Arc::new(Mutex::new(SessionManager::new(Path::new(
            &self.config.storage.sessions_path,
        ))?));
        let server = Server::bind(&listen_addr, adapter, sessions).await?;
        let local_addr = server.local_addr()?;
        let (shutdown_tx, shutdown_rx) = oneshot::channel();

        info!("agent runtime listening on {}", local_addr);

        let server_task = tokio::spawn(async move { server.run(shutdown_rx).await });
        let remote_task = match transport {
            Transport::Local { .. } => None,
            Transport::Remote {
                node_url,
                device_id,
                display_name,
                auth_token,
            } => {
                let local_server_url = format!("ws://127.0.0.1:{}/", local_addr.port());
                Some(tokio::spawn(async move {
                    loop {
                        match connect_and_register_remote(
                            &node_url,
                            &device_id,
                            &display_name,
                            &auth_token,
                        )
                        .await
                        {
                            Ok(remote_socket) => {
                                if let Err(error) = bridge_remote_socket_to_local_server(
                                    remote_socket,
                                    local_server_url.clone(),
                                )
                                .await
                                {
                                    warn!(?error, "remote transport bridge stopped");
                                }
                            }
                            Err(error) => {
                                warn!(?error, "connection node registration failed");
                            }
                        }

                        sleep(Duration::from_millis(500)).await;
                    }
                }))
            }
        };

        tokio::signal::ctrl_c()
            .await
            .context("failed to listen for ctrl+c")?;

        let _ = shutdown_tx.send(());
        if let Some(remote_task) = &remote_task {
            remote_task.abort();
        }
        server_task
            .await
            .context("server task join failed")?
            .context("server task failed")?;

        Ok(())
    }
}

pub async fn run_cli(cli: Cli) -> Result<()> {
    let config = load_config(cli.config.as_deref())?;
    let daemon = Daemon {
        config: apply_overrides(config, &cli),
    };
    daemon.run().await
}

fn load_config(path: Option<&Path>) -> Result<Config> {
    let Some(path) = path else {
        return Ok(Config::default());
    };

    let contents = fs::read_to_string(path)
        .with_context(|| format!("failed to read config file at {}", path.display()))?;
    toml::from_str(&contents)
        .with_context(|| format!("failed to parse config file at {}", path.display()))
}

fn apply_overrides(mut config: Config, cli: &Cli) -> Config {
    if cli.mock {
        config.agent.adapter = "mock".to_owned();
    }

    if let Some(listen) = &cli.listen {
        config.server.listen_addr = listen.clone();
    }

    if let Some(log_level) = &cli.log_level {
        config.log.level = log_level.clone();
    }

    config
}

fn create_adapter(config: &Config) -> Result<Box<dyn AgentAdapter>> {
    match config.agent.adapter.as_str() {
        "mock" => Ok(Box::new(MockAdapter::new())),
        "codex-cli" => Ok(Box::new(CodexCliAdapter::new())),
        "codex-app-server" => Ok(Box::new(CodexAppServerAdapter::new())),
        other => bail!("unsupported adapter '{other}'"),
    }
}

fn init_tracing(level: &str) {
    let filter = EnvFilter::try_new(level)
        .or_else(|_| EnvFilter::try_new("info"))
        .expect("tracing filter should parse");

    let _ = tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .try_init();
}
