#!/usr/bin/env zx

async function main() {
  console.log(`PATH: ${process.env.PATH}`);
  try {
    const { stdout, stderr } = await $`tmux has-session -t test_session_path_check`;
    console.log(`tmux stdout: ${stdout}`);
    console.log(`tmux stderr: ${stderr}`);
    console.log("tmux command executed successfully.");
  } catch (error) {
    console.error(`Error executing tmux: ${error}`);
    console.error(`Exit code: ${error.exitCode}`);
    console.error(`Stderr: ${error.stderr}`);
  }
}

main();
