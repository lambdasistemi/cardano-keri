# Data model — #374 headless simulator backends

Artifact ceiling: 4,500 bytes and 115 lines.

## DAT-374-TREE — backend session tree

- `family`: checkpoint or registry.
- `story`: selected checked-in scenario identity, or null for free play.
- `challenge`: selected built-in challenge identity, or null.
- `nodes`: non-empty ordered collection with exactly one origin at index zero.
- `cursor`: identity of one existing node.
- `actor`: current free-play actor.

The value contains no DOM node, event, timer, storage handle, or rendering
state. Calls do not mutate a previously returned tree or session value.

## DAT-374-NODE — one history/branch node

- Stable `id`, nullable `parent`, ordered `children`, and remembered `last`.
- Complete core `session` after the edge.
- Nullable core action `record`, actor/narration, kind, and optional branch
  identity and source-step expectation.
- A mismatch observation when replay differs from the scenario expectation.

Every non-origin node has one existing parent. Children point back to that
parent. A fork begins from its declared trunk prefix; hidden control steps add
no visible node. Refused actions preserve the input state in their new record
node.

## DAT-374-PATH — deterministic CLI projection

- Family, story/challenge, selected fork or trunk, cursor, and ordered
  origin-to-cursor nodes.
- For each edge: branch, slot, actor/narration, action, accepted/refused record,
  flow, resulting state, verdict, and theorem/lamp observations.
- Discovered and executed story, step, and fork denominators.

Projection order is stable and contains JSON values only.

## DAT-374-OFFERS — free-play choices

- Ordered KERI/evidence offers with label, evidence row, and explanation.
- Ordered chain offers with kind, label, and core action.

Offers derive only from explicit actor and session inputs.

## DAT-374-RESULT — caller-visible operation result

- Updated tree and selected cursor.
- Operation outcome: accepted value or named refusal with field/explanation.
- The added node/record when the operation is history-producing.

Invalid story, challenge, fork, node, actor, slot, evidence, or action input is
a closed refusal; it never produces a partial tree.

## DAT-374-EXTENT — proof denominator

- Discovered/executed checkpoint stories, scenario steps, and forks.
- Discovered/executed registry stories, scenario steps, and forks.

GREEN requires discovered equals executed, story counts 15/15, step counts
104/115, non-zero fork counts, and explicit refusal of zero or one-short
scratch extents.

