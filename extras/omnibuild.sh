#!/bin/sh
run_cmd=true
dry() {
  printf '\e[0;35m>> %s\e[0m\n' "$1" >&2
  [[ $run_cmd == true ]] && eval "$1"
}

optimize="ReleaseFast"
targets=(
    "x86_64-linux-musl"
    "aarch64-linux-musl"
    "riscv64-linux-musl"
    "x86_64-windows"
    "aarch64-windows"
    "x86_64-macos"
    "aarch64-macos"
    "x86_64-freebsd"
    "aarch64-freebsd"
    "riscv64-freebsd"
)

for i in "${targets[@]}"; do
  zig build -Doptimize=${optimize} -Dtarget=${i}
done

