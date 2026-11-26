# Build AOSP host tools

The first build host is Ubuntu 26.04 on Linux x86-64. The source lock selects the projects consumed from the AOSP Android 17.0.0 r1 manifest. The build uses the published AOSStudio JDK, the Go and Rust upstream distributions, and Clang from the host.

Install the host tools and library headers.

```sh
sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
  clang-21 llvm-21 build-essential cmake ninja-build pkg-config patch libssl-dev \
  zlib1g-dev libpng-dev libexpat1-dev protobuf-compiler python3-protobuf
```

Run the build from the repository root with Python 3.12 or later.

```sh
make build
make verify
```

`BUILD_JOBS` controls native compiler parallelism. `make fetch` verifies and populates the cache before a build. Each build group uses the same entry point independently. Run `make build-bootstrap` before `make build-generators` or `make build-java`; both use tools from its staged archive.

| Group | Package contents |
| --- | --- |
| `bootstrap` | `soong_ui`, `release-config`, `mk2rbc`, `rbcrun`, `ckati`, Android Ninja, Toybox, `sbox`, `soong_zip`, `merge_zips`, `zipsync` |
| `generators` | `aconfig`, `aconfig-to-metalava-flags`, AOSP 17 `aapt2` |
| `java` | Metalava, Turbine, `sdkparcelables`, launchers and runtime code |

Find the group archives under `out/dist/`. Each archive contains its licenses and input lock. Set `JAVA_HOME` to the extracted AOSStudio JDK when using the Java launchers. The flag-to-Metalava launcher uses the host Python Protobuf package.

The native build reads the public `cp2a` release configuration and compiles the resource flag library used by AAPT2. The standalone Cargo recipe uses the qualified Linux dependency graph. When invoking the packaged `soong_ui` directly, set `GOROOT` to the locked Go distribution. Soong bootstraps `soong_build` in the consumer's source tree so that its project-specific Blueprint modules and plugins are included.

The checks exercise the released configuration, the Kati/Ninja handoff, Soong ZIP actions, AAPT2 resource compilation and linking, Metalava's PSI and Turbine models, and Parcelable discovery. The SDK platform project consumes the host tools to build and package its API 37 platform.
