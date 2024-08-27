# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

<!-- Add your changelog entry to the relevant subsection -->

<!-- ### Added | Changed | Deprecated | Removed | Fixed | Security -->

<!--------------------- Don't add new entries after this line --------------------->

## [0.5.0] - 2024-08-27

### Fixed

- `FLAMEK8sBackend.RunnerPodTemplate`: Only set `PHX_SERVER` if it is not passed.
- `FLAMEK8sBackend.RunnerPodTemplate`: Reject `FLAME_PARENT`, not `FLAME_BACKEND` in passed env vars.

### Added

- `FLAMEK8sBackend.RunnerPodTemplate`: Set `.metadata.namespace` and `.metadata.generateName` on runner pod if not set ([#43](https://github.com/mruoss/flame_k8s_backend/pull/43))

### Changed

- `FLAMEK8sBackend.RunnerPodTemplate`: Also copy `env_from` if `add_parent_env` is `true`
- Improve documentation

## [0.4.3] - 2024-08-22

### Fixed

- use `FLAME.Parser.JSON` instead of `Jason`

### Added

- Support for BYO runner pod templates as map.

## [0.4.2] - 2024-07-28

### Fixed

- SSL cert verification workaround for older OTP versions was added again - [#37](https://github.com/mruoss/flame_k8s_backend/issues/37) [#38](https://github.com/mruoss/flame_k8s_backend/pull/38)
- Upgraded FLAME dependency to `0.3.0`

## [0.4.1] - 2024-07-07

### Changed

- Remove `Req` dependency and use `:httpc` instead in order to be safer when run in Livebook. [#35](https://github.com/mruoss/flame_k8s_backend/pull/35)

## [0.4.0] - 2024-06-19

### Changed

- Support for FLAME >= 0.2.0 and livebook integraion (requires livebook >= 0.13.0) - [#32](https://github.com/mruoss/flame_k8s_backend/pull/32)

## [0.3.3] - 2024-04-29

### Changed

- With `mint` 1.6.0 out, we have no need for the temporary workaround for TLS
  verification anymore.

## [0.3.2] - 2024-02-25

### Changed

- Dependency Updates

## [0.3.1] - 2024-01-28

### Changed

- Use `:cacertfile` insead of `:cacerts` in `:transport_options` and let the OTP process the certificate - [#8](https://github.com/mruoss/flame_k8s_backend/pull/8)
- Dependency Updates

## [0.3.0] - 2023-12-19

### Changed

- Remove`:insecure_skip_tls_verify` option and use a custom `match_fun` instead to work around failing hostname verification for IP addresses. - [#5](https://github.com/mruoss/flame_k8s_backend/pull/5)

## [0.2.3] - 2023-12-15

### Added

- `runner_pod_tpl` option for better control over the runner pod manifest - [#2](https://github.com/mruoss/flame_k8s_backend/pull/2)
- Basic integration test

### Changed

- Delete pod when shutting down the runner.

## [0.2.2] - 2023-12-14

### Fixed

- Don't crash the runner if the `:log` option is not set (or set to `false`)

## [0.2.1] - 2023-12-11

### Changed

- ENV var `DRAGONFLY_PARENT` was renamed to `FLAME_PARENT` in commit [9c2e65cc](https://github.com/phoenixframework/flame/commit/9c2e65ccd2c55514a473ad6ed986326576687064)

## [0.2.0] - 2023-12-10

### Changed

- Replace `k8s` lib with a lightweight Kubernetes client implementation.

## [0.1.0] - 2023-12-09

- Very early stage implementation of a Kubernetes backend.
