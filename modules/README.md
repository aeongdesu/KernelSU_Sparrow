# KernelSU modules

- `dfroot_boot_helper`
better than dfroot_whitelist trust


## auto builds
https://github.com/aeongdesu/KernelSU_Sparrow/releases/tag/ksu_modules

## dead
- ~~`dfroot_whitelist`~~
`ProcessIntercept` blocks 3rd party process starts triggered by boot broadcasts, so DFRoot `BootReceiver` is refused at `LOCKED_BOOT_COMPLETED / BOOT_COMPLETED` unless the package is on PICO VR whitelist\
so this module just adds dfroot app to whitelist\
please make sure **start on boot** option enabled in dfroot app!
