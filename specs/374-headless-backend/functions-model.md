# Functions model — #374 headless simulator backends

Artifact ceiling: 4,500 bytes and 115 lines.

Signatures describe the stable boundary; bodies and helpers are out of scope.
Each function exists in both family modules with family-specific domain values.

## Public backend operations

- **FUN-374-01** `playStory(storyId: number | string): BackendTree`
  - Builds the complete visible trunk/fork tree for one checked-in story.
- **FUN-374-02** `playChallenge(challengeId: string): BackendTree`
  - Builds the matching challenge origin or refuses an unknown identity.
- **FUN-374-03**
  `offersFor(actorId: string, tree: BackendTree, nodeId?: number): Offers`
  - Derives evidence and chain choices at the selected session.
- **FUN-374-04**
  `dryRun(tree: BackendTree, action: object, nodeId?: number): DryRunResult`
  - Observes the core verdict without adding a history node.
- **FUN-374-05**
  `submit(tree: BackendTree, actorId: string, action: object, nodeId?: number): OperationResult`
  - Adds an accepted or refused action record at the selected node.
- **FUN-374-06**
  `moveSlot(tree: BackendTree, targetSlot: number, nodeId?: number): OperationResult`
  - Adds a time node only for a valid forward slot change.
- **FUN-374-07**
  `addEvidence(tree: BackendTree, evidenceRow: object, nodeId?: number): OperationResult`
  - Adds a history node whose session contains the validated evidence row.
- **FUN-374-08**
  `removeEvidence(tree: BackendTree, evidenceRow: object, nodeId?: number): OperationResult`
  - Adds a history node whose session removes the selected evidence row.

## Tree selection and projection

- **FUN-374-09**
  `selectPath(tree: BackendTree, forkId: string | null, toEnd: boolean): BackendTree`
  - Selects only an existing trunk/fork path and its requested endpoint.
- **FUN-374-10** `projectJson(tree: BackendTree): BackendPathProjection`
  - Returns the stable JSON-only selected-path representation used by CLIs.

## CLI boundary

- **FUN-374-11**
  `runSimulatorCli(arguments: string[], writeOut: function, writeErr: function): Promise<number>`
  - Validates `--story`, optional `--fork`, `--to-end`, and `--json`, invokes
    only its backend, and maps closed refusals to non-zero status.

## Constraints

All operations validate references and domain inputs before changing a tree,
preserve safe-integer rules and core refusal names, expose no browser object,
and return no shared mutable aliases. The two modules keep these operation names
and result roles stable while retaining distinct machine state/action shapes.

