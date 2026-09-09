As a Serial server and HTTP web server welded together, this is not a sane product. I would not wish use of this 'product' in a professional setting on my worst enemy.
This is meant to log temperature data from a serial connected device. It reads logs in a format not included in this program.

## Zig Dependencies
| Name | URL |
| ---- | --- |
| Zig-Serial | https://github.com/ZigEmbeddedGroup/serial |
| http.zig | https://github.com/karlseguin/http.zig | 

## Compile-time dependencies
Hopefully none.

## Run-time dependencies
Hopefully none, especially with Linux MUSL builds.

## Compiling targets
The definition of "tested" in this scope consists of whether I have tested and verified that the program works reliably on this machine.
A lot of these platforms should work, but I have not tested them, whether I do not own the hardware, or I don't have the time to set up an environment.
| OS | ARCH | ABI | TESTED? |
| -- | ---- | --- | ------- |
| Linux | x86_64 | musl | Yes |
| Linux | x86_64 | gnu | No |
| Linux | aarch64 | musl | Yes |
| Linux | aarch64 | gnu | No |
| Linux | riscv64 | musl | No |
| Linux | riscv64 | gnu | No |
| Windows | x86_64 | gnu | Yes |
| Windows | aarch64 | gnu | No |
| MacOS | x86_64 | n/a | No |
| MacOS | aarch64 | n/a | No |

## Windows Notes:
There is a bug where there is a large delay (~20s) before the serial stream starts. 
I am unsure of the origin of this bug, and I am unsure where to start debugging this.

## MacOS Notes:
Zig-serial does not yet support listing available hardware as of this description being written, so this program does not either.
