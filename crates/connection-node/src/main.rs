use std::path::PathBuf;

use anyhow::{bail, Result};
use clap::{Args, Parser, Subcommand};
use connection_node::config::{AppConfig, StorageKind};
use connection_node::db::Database;
use connection_node::server;
use connection_node::user_cli::{add_user, list_users, render_users, reset_user, revoke_user};
use tracing_subscriber::EnvFilter;

#[derive(Debug, Parser)]
#[command(name = "connection-node")]
#[command(about = "Connection node bootstrap and user management CLI")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Run(RunCommand),
    User(UserCommand),
}

#[derive(Debug, Args)]
struct RunCommand {
    #[arg(long)]
    config: Option<PathBuf>,
}

#[derive(Debug, Args)]
struct UserCommand {
    #[command(subcommand)]
    command: UserSubcommand,
}

#[derive(Debug, Subcommand)]
enum UserSubcommand {
    Add(UserNameArg),
    List,
    Revoke(UserNameArg),
    Reset(UserNameArg),
}

#[derive(Debug, Args)]
struct UserNameArg {
    #[arg(long)]
    name: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Run(command) => {
            let config = AppConfig::load(command.config.as_deref())?;
            init_tracing(&config.log.level);
            let _db = open_database(&config)?;
            server::run(&config).await?;
        }
        Command::User(command) => {
            let config = AppConfig::load(None)?;
            init_tracing(&config.log.level);
            let db = open_database(&config)?;

            match command.command {
                UserSubcommand::Add(args) => {
                    let token = add_user(&db, &args.name)?;
                    println!("User '{}' created. Token: {}", args.name, token);
                }
                UserSubcommand::List => {
                    let users = list_users(&db)?;
                    println!("{}", render_users(&users));
                }
                UserSubcommand::Revoke(args) => {
                    revoke_user(&db, &args.name)?;
                    println!("User '{}' revoked.", args.name);
                }
                UserSubcommand::Reset(args) => {
                    let token = reset_user(&db, &args.name)?;
                    println!("User '{}' reset. Token: {}", args.name, token);
                }
            }
        }
    }

    Ok(())
}

fn init_tracing(level: &str) {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(level));
    let _ = tracing_subscriber::fmt().with_env_filter(filter).try_init();
}

fn open_database(config: &AppConfig) -> Result<Database> {
    match config.storage.kind {
        StorageKind::Sqlite => Database::open(&config.storage.path),
        StorageKind::Postgres => {
            bail!("managed PostgreSQL storage is out of scope for SPEC-NODE T01/T02")
        }
    }
}
