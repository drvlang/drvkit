//! Time a pinned Nix benchmark, or an explicitly supplied executable.
use std::env;
use std::ffi::OsString;
use std::process::{Command, ExitCode, Stdio};
use std::time::Instant;

struct Options {
    runs: usize,
    command: Vec<OsString>,
}
fn options() -> Result<Options, String> {
    let mut args = env::args_os().skip(1);
    let mut runs = 5;
    while let Some(arg) = args.next() {
        match arg.to_str() {
            Some("--runs") => {
                runs = args
                    .next()
                    .and_then(|v| v.to_str()?.parse().ok())
                    .filter(|r| (1..=1000).contains(r))
                    .ok_or("--runs needs an integer from 1 to 1000")?;
            }
            Some("--") => {
                let command: Vec<_> = args.collect();
                if command.is_empty() {
                    return Err("missing command after --".into());
                }
                return Ok(Options { runs, command });
            }
            _ => return Err("usage: drvbench [--runs N] [-- COMMAND [ARG ...]]".into()),
        }
    }
    Ok(Options {
        runs,
        command: vec![],
    })
}
fn measure(command: &[OsString]) -> Result<u128, String> {
    let (name, args) = command.split_first().ok_or("empty command")?;
    let start = Instant::now();
    let status = Command::new(name)
        .args(args)
        .stdout(Stdio::null())
        .status()
        .map_err(|e| format!("running {}: {e}", name.to_string_lossy()))?;
    if !status.success() {
        return Err(format!("{} exited with {status}", name.to_string_lossy()));
    }
    Ok(start.elapsed().as_micros())
}
fn run() -> Result<(), String> {
    let options = options()?;
    let mut command = options.command;
    let pinned = command.is_empty();
    if pinned {
        let target = env::var_os("DRVLANG_BENCH").ok_or("supply a benchmark command after --")?;
        command = ["nix", "build", "--no-link"].map(OsString::from).to_vec();
        command.push(target);
    }
    // Realize inputs and warm caches before collecting repeated samples.
    measure(&command)?;
    if pinned {
        command.insert(2, "--rebuild".into());
    }
    let mut samples = Vec::with_capacity(options.runs);
    for trial in 1..=options.runs {
        let elapsed = measure(&command)?;
        println!("run\t{trial}\t{elapsed} us");
        samples.push(elapsed);
    }
    samples.sort_unstable();
    let mid = samples.len() / 2;
    let median = (samples[(samples.len() - 1) / 2] + samples[mid]) as f64 / 2000.0;
    println!("median\t{median:.3} ms");
    Ok(())
}
fn main() -> ExitCode {
    if env::args_os()
        .nth(1)
        .is_some_and(|v| v == "--help" || v == "-h")
    {
        println!("Usage: drvbench [--runs N] [-- COMMAND [ARG ...]]");
        return ExitCode::SUCCESS;
    }
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("drvbench: {e}");
            ExitCode::FAILURE
        }
    }
}
