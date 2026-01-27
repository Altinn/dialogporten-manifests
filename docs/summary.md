# Dialogporten Flux manifests summary

This repo holds Flux manifests for Dialogporten on DIS. Flux is configured with a `GitRepository`
source that points to this repository and applies environment overlays.

## What is here
- `flux/dialogporten`: app configuration (base + environment overlays).
- `flux/syncroot`: Flux wiring for each environment (namespace, GitRepository, Kustomization).

## Environments
Overlays are in `flux/dialogporten/overlays/<env>`, and syncroot patches the Flux
`Kustomization.spec.path` to point at the corresponding overlay. Current environments:
`at23`, `tt02`, `yt01`, `prod`.
