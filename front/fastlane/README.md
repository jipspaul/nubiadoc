fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios distribute

```sh
[bundle exec] fastlane ios distribute
```

Build + distribue une app iOS. MODIFIE le compte Apple. Usage: fastlane ios distribute app:app_patient

### ios distribute_all

```sh
[bundle exec] fastlane ios distribute_all
```

Build + distribue les 4 apps iOS (MODIFIE le compte Apple)

### ios certs

```sh
[bundle exec] fastlane ios certs
```

Crée/synchronise les certificats + profils ad-hoc des 4 apps (match). MODIFIE le compte Apple.

----


## Android

### android distribute

```sh
[bundle exec] fastlane android distribute
```

Build + distribue une app. Usage: fastlane android distribute app:app_patient

### android distribute_all

```sh
[bundle exec] fastlane android distribute_all
```

Build + distribue les 4 apps

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
