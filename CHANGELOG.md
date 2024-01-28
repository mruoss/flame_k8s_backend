# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

<!-- Add your changelog entry to the relevant subsection -->

<!-- ### Added | Changed | Deprecated | Removed | Fixed | Security -->

<!--------------------- Don't add new entries after this line --------------------->

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
