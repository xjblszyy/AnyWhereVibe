use clap::Parser;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    agent::daemon::run_cli(agent::daemon::Cli::parse()).await
}
