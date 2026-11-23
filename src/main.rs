//! CLI shared by the drvlang package builders.
use std::env;
use std::ffi::OsString;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::PathBuf;
use std::process::{Command, ExitCode, ExitStatus};

fn exit_code(status: ExitStatus) -> ExitCode {
    ExitCode::from(
        status
            .code()
            .or_else(|| status.signal().map(|s| s + 128))
            .unwrap_or(1) as u8,
    )
}

fn run() -> Result<ExitCode, String> {
    let tool = env::var("DRVLANG_TOOL").unwrap_or_else(|_| "drv".into());
    let usage = format!("Usage: {tool} build|test|run [-C PROJECT] [TARGET] [-o RESULT | --no-link] [--options JSON] [-- ARGS...]");
    let mut args = env::args_os().skip(1);
    let operation = match args.next().as_deref().and_then(|v| v.to_str()) {
        None | Some("-h" | "--help") => {
            println!("{usage}");
            return Ok(ExitCode::SUCCESS);
        }
        Some(op @ ("build" | "test" | "run")) => op.to_owned(),
        _ => return Err(usage),
    };
    let mut project = PathBuf::from(".");
    let mut link: Option<OsString> = None;
    let mut target = None;
    let mut no_link = false;
    let mut options = OsString::from("{}");
    let mut forwarded = Vec::new();
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
            Some("--") => {
                forwarded.extend(args);
                break;
            }
            Some(s) if !s.starts_with('-') && target.is_none() => target = Some(arg),
            _ => {
                return Err(format!(
                    "unexpected argument {}\n{usage}",
                    arg.to_string_lossy()
                ))
            }
        }
    }
    if no_link && link.is_some() {
        return Err("choose either --no-link or --out-link".into());
    }
    if operation == "build" && !forwarded.is_empty() {
        return Err("arguments after -- apply to test or run".into());
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
        .args([
            "build",
            "--impure",
            "--option",
            "allow-import-from-derivation",
            "false",
            "--print-out-paths",
            "--file",
        ])
        .arg(entry)
        .args(["--argstr", "directory"])
        .arg(project)
        .args(["--argstr", "operation", &operation])
        .args(["--argstr", "target"])
        .arg(target.unwrap_or_default())
        .args(["--argstr", "options"])
        .arg(options);
    if let Some(link) = link {
        command.arg("--out-link").arg(link);
    } else if no_link || operation != "build" {
        command.arg("--no-link");
    }
    if operation == "test" {
        command
            .args(["--argstr", "testArgCount"])
            .arg(forwarded.len().to_string());
        for (index, arg) in forwarded.iter().enumerate() {
            command.env(format!("DRVLANG_TEST_ARG_{index}"), arg);
        }
    }
    if operation != "run" {
        return command
            .status()
            .map(exit_code)
            .map_err(|e| format!("running nix: {e}"));
    }
    command.stderr(std::process::Stdio::inherit());
    let result = command.output().map_err(|e| format!("running nix: {e}"))?;
    if !result.status.success() {
        return Ok(exit_code(result.status));
    }
    let path = std::str::from_utf8(&result.stdout)
        .map_err(|_| "invalid store path")?
        .trim_end();
    if !PathBuf::from(path).is_absolute() || path.contains('\n') {
        return Err("expected one executable store path".into());
    }
    Err(format!(
        "running {path}: {}",
        Command::new(path).args(forwarded).exec()
    ))
}

fn main() -> ExitCode {
    run().unwrap_or_else(|error| {
        eprintln!("{error}");
        ExitCode::FAILURE
    })
}
