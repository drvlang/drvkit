//! Shared command-line entry point for drvlang Nix builders.
use std::env;
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

fn run() -> Result<ExitCode, String> {
    let tool = env::var("DRVLANG_TOOL").unwrap_or_else(|_| "drv".into());
    let usage =
        format!("Usage: {tool} build [-C PROJECT] [-o RESULT | --no-link] [--options JSON]");
    let mut args = env::args_os().skip(1);
    match args.next().as_deref().and_then(|s| s.to_str()) {
        None | Some("-h" | "--help") => {
            println!("{usage}");
            return Ok(ExitCode::SUCCESS);
        }
        Some("build") => {}
        _ => return Err(usage),
    }
    let mut project = PathBuf::from(".");
    let mut link: Option<OsString> = None;
    let mut no_link = false;
    let mut options = OsString::from("{}");
    while let Some(arg) = args.next() {
        match arg.to_str() {
            Some("-C" | "--directory") => {
                project = args.next().ok_or("missing project directory")?.into()
            }
            Some("-o" | "--out-link") => link = Some(args.next().ok_or("missing result path")?),
            Some("--no-link") => no_link = true,
            Some("--options") => options = args.next().ok_or("missing JSON options")?,
            Some("-h" | "--help") => {
                println!("{usage}");
                return Ok(ExitCode::SUCCESS);
            }
            _ => return Err(format!("unknown option {}\n{usage}", arg.to_string_lossy())),
        }
    }
    if no_link && link.is_some() {
        return Err("choose either --no-link or --out-link".into());
    }
    let project = project
        .canonicalize()
        .map_err(|e| format!("{}: {e}", project.display()))?;
    if !project.is_dir() {
        return Err(format!("{} is not a directory", project.display()));
    }
    let entry = env::var_os("DRVLANG_ENTRY").ok_or("missing packaged Nix entry point")?;
    let mut command = Command::new("nix");
    command
        .args(["build", "--impure", "--print-out-paths", "--file"])
        .arg(entry)
        .args(["--argstr", "directory"])
        .arg(project)
        .args(["--argstr", "options"])
        .arg(options);
    if no_link {
        command.arg("--no-link");
    }
    if let Some(link) = link {
        command.arg("--out-link").arg(link);
    }
    let status = command.status().map_err(|e| format!("running nix: {e}"))?;
    Ok(ExitCode::from(
        status
            .code()
            .and_then(|c| u8::try_from(c).ok())
            .unwrap_or(1),
    ))
}
fn main() -> ExitCode {
    run().unwrap_or_else(|e| {
        eprintln!("{e}");
        ExitCode::FAILURE
    })
}
