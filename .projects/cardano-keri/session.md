# cardano-keri project session map

## Project owner

```text
session       projects
window        cardano-keri
pane          %6429
role          project-orchestrator
cwd           /home/paolino
runtime       /tmp/projects/cardano-keri
launch        codex-raw --dangerously-bypass-approvals-and-sandbox -C /home/paolino -c model_reasoning_effort=xhigh
resume        /tmp/projects/cardano-keri/STATUS.md then this branch's .projects/cardano-keri/resume.md
```

The same project window currently retains pane `%6656`, an operator-requested
terminal Opus audit context. It is not a project-owner peer and owns no M1.2
work.

## M1 — custodial-terminal

```text
session       keri
window        cardano-keri-ms1-identity-core
pane          %5511
role          milestone-orchestrator
runtime       /tmp/ms-keri-1
state         custodial-terminal; do not reopen
```

## M1.2 / GitHub milestone 11 — active

```text
session       keri-m12
window        cardano-keri-ms11-decomposed-record-cursor
pane          %6695
role          milestone-orchestrator
cwd           /code/cardano-keri
runtime       /tmp/ms-keri-11
launch        claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high
brief         /tmp/ms-keri-11/brief.md
brief sha256  44a18628e08a4394adae1a6021e00aa7cfa1466551547707a5db72f077d7813e
START         2026-08-18T09:24:05Z
scope         S0+S1 active; backlog rulings accepted; exact issue payload local-only; conditional S2+decoder prepared/inactive
next barriers exact issue-payload acceptance for C; S0+S1 package -> project M12-S2-ACTIVATED for A/B
```

## M8 — parked

```text
session       keri-ms8-blaster
window        cardano-keri-ms8-blaster
pane          %5331
role          milestone-orchestrator
runtime       /tmp/ms-keri-8
state         parked under OMNIA PAUSA; not released by M1.2 founding
```
