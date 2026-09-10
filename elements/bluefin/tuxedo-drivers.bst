kind: manual
description: |
  Out-of-tree kernel modules and udev hardware quirks for TUXEDO laptops.
  Provides platform drivers, keyboard backlight, fan and power sensors,
  and /dev/tuxedo_io for Clevo and Uniwill/Tongfang ODM chassis.

build-depends:
- freedesktop-sdk.bst:bootstrap/coreutils.bst
- freedesktop-sdk.bst:bootstrap/bash.bst
- freedesktop-sdk.bst:components/_private/gcc-base.bst
- freedesktop-sdk.bst:bootstrap/binutils.bst
- freedesktop-sdk.bst:components/make.bst
- freedesktop-sdk.bst:components/linux.bst
# Kernel's objtool is dynamically linked against libxxhash.so.0
- freedesktop-sdk.bst:components/xxhash.bst

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

sources:
- kind: git_repo
  url: gitlab:tuxedocomputers/development/packages/tuxedo-drivers.git
  track: main
  ref: 2c6bf54075fb38a7fdbefc560734281984bf65bc

config:
  build-commands:
  - |
    set -euo pipefail
    KVER=""
    for d in /usr/lib/modules/*; do
        if [ -d "$d" ]; then
            if [ -n "$KVER" ]; then
                echo "FATAL: multiple kernel directories found under /usr/lib/modules: $KVER and $(basename "$d")" >&2
                exit 1
            fi
            KVER=$(basename "$d")
        fi
    done
    if [ -z "$KVER" ] || [ ! -d "/usr/lib/modules/$KVER/build" ]; then
        echo "FATAL: no kernel build tree found under /usr/lib/modules" >&2
        exit 1
    fi
    echo "Building TUXEDO kernel modules against $KVER"
    make -j${BST_BUILD_THREADS:-1} -C "/usr/lib/modules/$KVER/build" M="$PWD" modules

  install-commands:
  # depmod is intentionally deferred to OCI layer composition time
  - |
    set -euo pipefail
    KVER=""
    for d in /usr/lib/modules/*; do
        if [ -d "$d" ]; then
            if [ -n "$KVER" ]; then
                echo "FATAL: multiple kernel directories found under /usr/lib/modules: $KVER and $(basename "$d")" >&2
                exit 1
            fi
            KVER=$(basename "$d")
        fi
    done
    make -j1 -C "/usr/lib/modules/$KVER/build" M="$PWD" modules_install \
        INSTALL_MOD_PATH="%{install-root}%{prefix}" \
        DEPMOD=/bin/true
  - |
    set -euo pipefail
    # Install hardware quirks, udev rules, and modprobe configuration
    if [ -d files/usr ]; then
        cp -r files/usr/* "%{install-root}%{prefix}/"
    fi
