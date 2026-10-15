# marinara-flake

A Nix flake that provides [Marinara Engine](https://github.com/Pasta-Devs/Marinara-Engine), an AI chat, roleplay, and game frontend, built from upstream source.

```
nix build .#marinara
./result/bin/marinara-engine
```

## What you get

| Attribute | Description |
| --- | --- |
| `packages.<system>.marinara` | The Marinara server as a single launchable command, `marinara-engine`. |
| `packages.<system>.default` | The same package. |
| `packages.<system>.marinara.passthru.runtimeRootfs` | An empty filesystem hierarchy to copy into a container image root. See [Container use](#container-use). |

The launcher carries its own toolchain — Node, `pnpm`, `python3`, and bubblewrap are all resolved from the package, not from the host — and starts the server in its application directory.

## Platform support

Linux only. Asking for another system reports the package as unsupported.

## Host requirements

The server sandboxes its tool execution with bubblewrap, which needs unprivileged user namespaces available wherever the server runs — including inside a container, where the container runtime decides whether they are permitted. A host that restricts them cannot create the sandbox.

Native dependencies (image and inference runtimes) resolve against the C++ runtime, OpenSSL, and a Vulkan loader, all supplied by the package. A Vulkan *driver* is not: CPU inference works as-is, and a GPU-enabled deployment supplies its own driver and makes it visible in the container or on the host.

## Container use

`runtimeRootfs` is a filesystem skeleton — directories only, no packages. Copy it onto the image root so that the loader paths the server searches for exist; the package's own closure arrives with the package, not from here. It is not a base image and contains no runtime dependencies.

## License

Marinara Engine is AGPL-3.0-only. This flake redistributes nothing: it builds from upstream source at build time, and the result remains governed by upstream's license.

One allowance is worth knowing about, because it changes what you are shipping. The pnpm release upstream pins is marked insecure by nixpkgs, which refuses to evaluate it; this flake permits that one release by name so the build proceeds. The advisories nixpkgs records against it are current as of its nixpkgs revision. The pinned pnpm is present at runtime, not only during the build, because the server invokes it.
