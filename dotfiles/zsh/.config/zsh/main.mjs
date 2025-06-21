#!/usr/bin/env zx
// Autogenerates aliases for every  *.mjs  inside  ~/.config/zsh/scripts

const DIR = `${process.env.HOME}/.config/zsh/scripts`;
const { stdout } = await $`ls -1 ${DIR}/*.mjs 2>/dev/null || true`;

for (const f of stdout.trim().split("\n").filter(Boolean)) {
  // WAIT for basename to finish and take its .stdout
  const name = (await $`basename -s .mjs ${f}`).stdout.trim();
  console.log(`alias ${name}='zx "${f}" "$@"'`);
}

// TODO fix it
