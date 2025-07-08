#!/usr/bin/env zx

import path from "path";
import fs from "fs/promises";

const currentDir = process.cwd();
const sessionName = path.basename(currentDir);

let tmuxPath;

async function getTmuxPath() {
  try {
    const { stdout } = await $`which tmux`;
    tmuxPath = stdout.trim();
  } catch (error) {
    console.error(
      "Error: 'tmux' command not found in your PATH. Please ensure tmux is installed and accessible.",
    );
    process.exit(1);
  }
}

async function runCommand(command, ...args) {
  try {
    await $`${tmuxPath} ${command} ${args}`;
  } catch (error) {
    // Re-throw the error so the calling function can handle it
    throw error;
  }
}

async function main() {
  await getTmuxPath(); // Determine tmux path once at the start

  try {
    const stats = await fs.stat(currentDir);
    if (!stats.isDirectory()) {
      console.error(`Error: ${currentDir} is not a directory.`);
      process.exit(1);
    }
  } catch (error) {
    if (error.code === "ENOENT") {
      console.error(`Error: Directory not found: ${currentDir}`);
    } else {
      console.error(
        `Error accessing directory ${currentDir}: ${error.message}`,
      );
    }
    process.exit(1);
  }

  let sessionExists = false;
  try {
    // Check if session exists
    await runCommand(`has-session`, `-t`, sessionName);
    sessionExists = true;
  } catch (error) {
    // This catch block is specifically for when 'tmux has-session' fails,
    // indicating the session does not exist.
    if (error.stderr && error.stderr.includes("can't find session")) {
      sessionExists = false;
    } else {
      // For any other unexpected error from runCommand, re-throw or log and exit
      console.error(
        `An unexpected error occurred: ${error.stderr || error.message}`,
      );
      process.exit(1);
    }
  }

  if (sessionExists) {
    console.log(`Attaching to existing tmux session: ${sessionName}`);
  } else {
    console.log(`Creating new tmux session: ${sessionName}`);

    // Create new session with window 0 (terminal)
    await runCommand(`new-session`, `-d`, `-s`, sessionName, `-c`, currentDir);

    // Window 1: nvim
    await runCommand(
      `new-window`,
      `-t`,
      `${sessionName}:1`,
      `-n`,
      `nvim`,
      `-c`,
      currentDir,
    );
    await runCommand(`send-keys`, `-t`, `${sessionName}:1`, `nvim .`, `C-m`);

    // Window 2: venv_terminal
    await runCommand(
      `new-window`,
      `-t`,
      `${sessionName}:2`,
      `-n`,
      `venv_terminal`,
      `-c`,
      currentDir,
    );
    const venvCheck = `if [ -d ".venv" ]; then source .venv/bin/activate; elif [ -d "venv" ]; then source venv/bin/activate; fi`;
    await runCommand(`send-keys`, `-t`, `${sessionName}:2`, venvCheck, `C-m`);

    // Window 3: gemini_command
    await runCommand(
      `new-window`,
      `-t`,
      `${sessionName}:3`,
      `-n`,
      `gemini_command`,
      `-c`,
      currentDir,
    );
    await runCommand(`send-keys`, `-t`, `${sessionName}:3`, `gemini`, `C-m`);

    // Select the first window (terminal)
    await runCommand(`select-window`, `-t`, `${sessionName}:0`);
  }

  console.log(`
To attach to this session, copy and paste the following command:
${tmuxPath} attach-session -t ${sessionName}
`);
}

main();

