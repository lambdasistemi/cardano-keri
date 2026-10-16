# Plan

S279-1: One isolated public-chain inventory command and permanent falsification suite, followed by a dated live evidence report. Keep existing application and validator behavior unchanged. Reuse deployed schema definitions and existing golden byte vectors as the wire authority; support both ARMED wire versions in the inspection tool.

The deployed manifest at base 5a35284 names source 50a582064ddfde15ebfa3649c6b6fea8d39fc697 and policy 0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734. Existing koiosLiveCheckpoints is ACTIVE-address-only and is insufficient for this ticket. A payment-credential scan plus policy-asset reconciliation spans role addresses; unknown locations stay visible. Public Koios is available without credentials.

The live scope is currently unspent identities under the manifest deployment, not all historical burned identities or undiscovered deployments. Resolve that boundary explicitly in the report. Reports distinguish an interval observed through an indexer from an atomic ledger snapshot.

Owner mode with alternate-family implementation, pre-work gate review, fresh independent final inspection, no merge. No edits to other lanes. Planning artifacts capped at 120 lines each; compiled child brief capped at 160 lines. New implementation and permanent tests capped at 900 lines together; challenge rather than evade the ceiling.
