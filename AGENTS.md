# Automated Build Agent Instructions

## Objective
Create Fedora-based toolboxes for ROCm and PyTorch targeting the `gfx1151` and `gfx1209` GPU architectures. The final output must be at least one podman image capable of being used as the base to construct a toolbox environment under Fedora. Both ROCm and PyTorch must be pinned to the `7.2.1` version.

## Target Architecture & Stack
- **Base OS**: Fedora 43 (must be configured to support `toolbox`/`distrobox`)
- **Container Technology**: Podman (Primary container tool)
- **Container Type**: Fedora Toolboxes (NOT Ubuntu containers)
- **GPU Architectures**: `gfx1151` (Strix Halo) and `gfx1209`
- **ROCm Version**: 7.2.1
- **PyTorch Version**: Target version compatible with ROCm 7.2.1
- **Additional Tools**: PyTorch must have `aotriton` included at minimum. Including `aiter` is desired but optional at the beginning, depending on required patches.

## Reference Material
- There is a reference repository mapped out in `./tmp/ML-gfx900`. This provides an example of how to build *Ubuntu-based* containers for older architectures.
- A critical reference file is `tmp/ML-gfx900/rocm/toolbox.rocm.Dockerfile`. This demonstrates the exact Podman approach for creating a `toolbox`-compatible image. It shows the necessary labels (`com.github.containers.toolbox="true"`) and system hacks (like clearing `/etc/machine-id` for DBUS propagation, `nsswitch.conf` modifications, and removing default users mapped to UID 1000) that make the podman container actually run via the `toolbox` utility.
- The `pytorch` subfolder demonstrates a layered Podman build script approach, compiling natively on top of the previously built ROCm toolbox base.
- **Goal extraction**: We want to extract this exact conceptual layered approach—building a ROCm toolbox base, and then a PyTorch one on top—but targeting **Fedora** instead of Ubuntu. The coding agents must translate the Ubuntu `apt-get` system hacks from `toolbox.rocm.Dockerfile` to their equivalent Fedora RPM dependencies and `dnf` syntax, tailored specifically for the `gfx1151` and `gfx1209` architectures. Do NOT copy the Ubuntu syntax verbatim.

## Operational Rules & Constraints for Coding Agents

### 1. Zero Hallucination & Strict Source Data Policy
The ROCm and PyTorch support landscape for bleeding-edge architectures like `gfx1151` and `gfx1209` changes daily. 
**DO NOT rely on your pre-trained LLM knowledge or hallucinated information.**
You must verify all package names, capability flags, compatible versions, and repository links against *live, current systems*.

### 2. Verify Online Claims with the Source
If you conduct web un-authenticated searches ("googling") for documentation:
- Ensure the documentation is recent.
- Double-check what you read against live codebases, GitHub issues in the `amd`, `ROCm`, or `pytorch` repositories, and build artifacts.
- Pull the `rocm-systems` repository (or similar) into a temporary directory if needed and *read its source code and patches* for evidence of flag usage, compatibility matrices, and required workarounds.
- Base your decisions strictly on empirical evidence gathered dynamically.

### 3. Systematic Testing & Execution
- Research the target toolchain on Fedora. Look at current RPMs available dynamically if possible, or build logic needed to fulfill toolboxes.
- Ensure any `Dockerfile`/`Containerfile` produced complies with standard Podman caching logic.
- Before claiming completion or assuming something works, check that the steps make logical sense against the latest patches and build configurations available for ROCm 7.2.1.
- Make iterative progress. Research -> Read codebases -> Validate assumptions -> Write instructions -> Test.

### 4. Code & Build Practices
- Follow standard build configurations (e.g. configuring `PYTORCH_ROCM_ARCH="gfx1151;gfx1209"` properly in the build environments).
- Structure the project elegantly, separating out logical components (e.g., base container build scripts vs PyTorch compilation logic vs toolbox provisioning).

### 5. Execution Environment
- **NO LOCAL BUILDS**: This is a development workstation. DO NOT use Podman or build things locally on this machine.
- **Read-Only Local Tools**: You may download source code from GitHub, read documentation, and perform searches, but this is explicitly NOT the place where the toolboxes are built.
- **Remote Execution**: If you need to run something (like test a Podman build or query DNF on the build server), you MUST notify the user, provide the command, and let the user execute it for you.
