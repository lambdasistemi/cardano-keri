# Fifteen identity stories — 2027-02-20 preprod target

**D-09 story.** As a preprod integrator, I want the identity lifecycle and its forks to run through released keripy and `ckeri` commands, so that I can inspect the real chain effects and refusals before relying on the interface.

This is a dated review target from the [project card](https://github.com/orgs/lambdasistemi/projects/4/views/5). The existing checkpoint simulator contains fifteen scenario fixtures, but running them through Node does not submit a Cardano transaction. A model-only recording is not the D-09 demo.

## Planned preprod play

Each story must start from a reachable preprod output produced by the previous keripy and `ckeri` commands. The presenter uses `kli` to generate the KERI event, exports its CESR stream, submits the corresponding `ckeri` command, then reads the exact transaction and state back from preprod. Forks that promise a refusal must send their evidence to the intended client or validator boundary and show the observed error. The run records release identity, manifest, AID, script and policy IDs, transaction IDs, values and uncovered rows.

```mermaid
sequenceDiagram
    participant Actor
    participant KLI as keripy kli
    participant CKERI as ckeri
    participant Chain as Cardano preprod
    Actor->>KLI: Create the next KERI event
    KLI-->>CKERI: CESR and receipts
    CKERI->>Chain: Submit the story action
    Chain-->>CKERI: Transaction or script refusal
    CKERI-->>Actor: Fresh status and evidence row
```

The local fixture replay does not establish this journey. The full checkpoint scenario gate at the current source revision is also RED on theorem-row, story-reconciliation and fabricated-violation checks. A preprod cast will be attached only after the connected story runner and its named controls execute. Until then, this page is a play plan.

## Presenter path: 10–15 minutes when connected

| Time | Action | Required observation |
| --- | --- | --- |
| 0–2 min | Show the release, manifest, keripy version and funded preprod starting state. | Exact artifact and model identities. |
| 2–6 min | Run representative controller and hunter stories. | CESR events, confirmed `ckeri` transactions and state readbacks. |
| 6–10 min | Run close, return and conviction forks. | Actual registry and checkpoint effects with values. |
| 10–13 min | Run named negative controls. | Client or script attribution for each observed refusal. |
| 13–15 min | Review the fifteen-row receipt table. | All exercised rows, unresolved rows and gate failures stay visible. |

## Missing interface and evidence

A released connected D-04 through D-08 command path, preprod funding and manifests, a fifteen-story runner, transaction receipts, negative controls and an uncovered-row report remain required. The [Lean correspondence register #435](https://github.com/lambdasistemi/cardano-keri/issues/435) controls affected semantics. No preprod suite acceptance is claimed.
