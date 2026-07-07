# Finance & Institutions Primer

The business-case documents lean on concepts from traditional finance and
financial regulation. This page explains them from zero — the same way the
[KERI primer](keri-primer.md) explains identity concepts. Each section is
linkable; the case studies point here on first use of a term.

Nothing on this page is legal advice, and definitional summaries are not
claims about what regulation requires of this project — see the
regulation-vs-implementation rule stated in
[The Regulated DeFi Gate](design/defi-gate.md).

---

## Instruments — the things being traded

### Security

A tradable financial instrument that represents a claim on something: a share
of a company (equity), a loan to a company or state (bond), a slice of a fund.
What makes securities special is that nearly every jurisdiction regulates who
may issue them, who may buy them, and how they may change hands. That is why
"put a security on a blockchain" is never just a token drop — the transfer
rules come with the asset. See the U.S. regulator's plain-language
introduction: https://www.investor.gov/introduction-investing

### Bond, fund, money-market fund

A **bond** is a tradable loan: the issuer owes the holder repayment plus
interest. A **fund** pools money from many investors and invests it under a
mandate; investors hold shares of the pool. A **money-market fund** is a fund
that holds only very short-term, very safe debt (e.g. government treasuries) —
functionally "a bank account paying market interest." Tokenized money-market
funds are the first institutional products that demonstrably exist on public
chains (e.g. BlackRock's BUIDL, Franklin Templeton's on-chain fund), and every
one of them restricts who may hold it.

### Private placement

Selling a security directly to a small circle of professional investors
instead of the general public. Regulators allow this with far lighter
paperwork (in the EU, exemptions from the prospectus — the heavyweight public
disclosure document: https://eur-lex.europa.eu/eli/reg/2017/1129/oj) — but in
exchange the security typically **cannot be freely resold**: transfers are
restricted to other eligible investors. This is why transfer restriction is a
legal property of the asset class, not a policy choice, and why the
[security-tokens case](design/business-cases/security-tokens.md) picks a
private placement as the smallest lawful pilot.

### RWA — real-world assets

Crypto-industry shorthand for tokenized versions of off-chain assets: funds,
bonds, private credit, real estate. The "RWA issuer" is the legal entity that
puts such an asset on-chain — and inherits its transfer-restriction
obligations, which is what makes RWA issuers the natural paying customer for
identity gating.

---

## Market plumbing — how ownership and settlement actually work

### Register vs bearer instrument

Two opposite models of proving ownership. A **bearer instrument** is owned by
whoever physically holds it (cash, or a plain crypto token in your wallet). A
**registered security** is owned by whoever the official **register** says
owns it — the paper certificate is just a receipt. Modern securities are
almost all registered: the register is authoritative, the instrument is not.
This distinction drives the two design variants in the
[security-tokens case](design/business-cases/security-tokens.md): wrap the
token so it can never move unchecked (bearer-style, restricted), or make the
on-chain trie *be* the register (register-style — closest to legal reality).

### Transfer agent / registrar

The entity legally responsible for keeping the register: recording transfers,
freezing positions, executing court orders, fixing errors. See the U.S.
regulator's description: https://www.sec.gov/about/divisions-offices/division-trading-markets/transfer-agents
On-chain, most of this role dissolves into the validator — but not the
override powers (freeze, court-ordered seizure), which is why the
security-tokens design deliberately reintroduces a scoped issuer power.

### CSD — central securities depository

The institution at the top of a market's settlement plumbing: it holds the
master register for entire markets and settles trades between banks (e.g.
Euroclear, or the ECB's T2S platform:
https://www.ecb.europa.eu/paym/target/t2s/html/index.en.html). Mentioned in
the case studies because operating a securities register can make *you* look
like a CSD or transfer agent to a regulator — the "securities-law perimeter"
risk.

### Custody

Holding assets (or keys) on someone else's behalf. Institutions rarely hold
their own instruments directly — a **custodian** bank does, under strict
duties. "Board-level custody of the LE root key" in the case studies means:
the entity's master identity key is treated like a corporate seal, locked
behind multi-person control, and never used for day-to-day operations — which
is why the *acting* credential is always a role credential
([OOR/ECR](design/vlei.md)), not the entity's root key.

### Settlement and DvP

**Settlement** is the actual exchange of asset for payment after a trade is
agreed. **DvP — delivery versus payment** — means the two legs happen
atomically: you cannot end up having paid without receiving, or delivered
without being paid (the risk otherwise is called settlement risk; see the BIS
principles: https://www.bis.org/cpmi/publ/d101.htm). A blockchain transaction
is naturally DvP — both legs in one atomic transaction — which is a genuine
advantage the [institutional-contracts case](design/business-cases/institutional-contracts.md)
builds on.

### Escrow

A neutral arrangement that holds an asset until agreed conditions are met,
then releases it (house purchases are the everyday example). On-chain: a
contract UTxO whose validator releases funds only when the agreed transition
fires — no neutral *party* needed, only a neutral *script*.

### Repo

A **repurchase agreement**: party A sells securities to party B and commits to
buying them back later at a slightly higher price — economically a
collateralized short-term loan. A workhorse of interbank finance (see ICMA's
explainer: https://www.icmagroup.org/market-practice-and-regulatory-policy/repo-and-collateral-markets/)
and a natural fit for a multi-transition contract state machine
(open → roll → close).

### Syndication

Splitting one large position (typically a loan) across several institutions,
each holding a share. Transfers of shares between members are exactly the
kind of few-party, identity-sensitive transition the institutional-contracts
templates target.

---

## Compliance — the rules the actors live under

### KYC — know your customer

The obligation of a regulated business to verify who its customer is before
serving them (identity documents for people, registry extracts and ownership
structure for companies). The global standard-setter is the FATF:
https://www.fatf-gafi.org/en/topics/fatf-recommendations.html — but note
carefully: the obligation sits on the *regulated business*, never on the
blockchain. cardano-aid does not perform KYC; QVIs do, when they issue
credentials.

### AML and sanctions screening

**Anti-money-laundering**: the wider duty to monitor, detect and report
suspicious flows — an ongoing process, not a one-time identity check.
**Sanctions screening**: checking counterparties against government blocklists
(e.g. the EU sanctions map: https://www.sanctionsmap.eu) that change on a
day's notice. The case studies repeatedly state that registry freshness is
"minutes-grade, never sanctions-screening-grade": an on-chain gate can prove
*who* someone is, but real-time blocklist compliance remains an off-chain
institutional process.

### LEI and GLEIF

The **Legal Entity Identifier** is a 20-character global company ID, created
by the G20 after the 2008 crisis so that regulators could finally answer "who
is exposed to whom." **GLEIF** is the foundation that operates the system:
https://www.gleif.org/en/about-lei/introducing-the-legal-entity-identifier-lei
The **vLEI** is GLEIF's cryptographic upgrade of the LEI — the credential
chain at the heart of this project (see [vLEI Bridge](design/vlei.md)). When
the docs say "the trust root regulators already accept," this is it.

### MiFID II, Basel III, eIDAS 2.0, MiCA

The four regulatory frameworks named in these docs, in one line each:

| Framework | One-liner | Reference |
|---|---|---|
| **MiFID II** | EU rulebook for investment services and trading venues; requires LEIs on transaction reports | https://www.esma.europa.eu/trading/mifid-ii-and-mifir |
| **Basel III** | Global bank-capital standards; banks must identify counterparty exposure robustly | https://www.bis.org/bcbs/basel3.htm |
| **eIDAS 2.0** | EU digital-identity regulation; member states must offer identity wallets | https://digital-strategy.ec.europa.eu/en/policies/eudi-regulation |
| **MiCA** | EU regulation of crypto-asset services and issuers | https://eur-lex.europa.eu/eli/reg/2023/1114/oj |

!!! warning "These are identification frameworks, not gating mandates"
    None of these say "DeFi must gate." They establish that machine-verifiable
    *entity identification* is what regulators run on. Any stronger claim in
    project docs requires an article-level citation first.

### DLT Pilot Regime

An EU regulation (https://eur-lex.europa.eu/eli/reg/2022/858/oj) creating a
sandbox in which market infrastructure for *tokenized* securities may operate
with tailored exemptions — the current EU on-ramp for anything resembling an
on-chain securities register.

### Court-ordered seizure, freeze, forced transfer

Legal system powers over registered assets: a court can order a holder's
position frozen or transferred (fraud, insolvency, sanctions). A securities
register that *cannot* execute such orders is not legally operable — which is
why "the oracle cannot touch leaves," a virtue everywhere else in cardano-aid,
must be deliberately relaxed into a scoped, auditable issuer power for the
security-tokens case.

---

## DeFi market structure — the on-chain side

### DEX, AMM, liquidity provider

A **DEX** (decentralized exchange) is a trading venue that is a smart
contract. Most are **AMMs** (automated market makers): instead of matching
buyers with sellers, a pool holds both assets and quotes a price from a
formula. **Liquidity providers** deposit assets into the pool and receive
**LP tokens** representing their share. Relevant here because LP-token minting
is one of the enforcement points where an identity gate can bite.

### Batcher model

On Cardano, a pool is one UTxO, and only one transaction can spend a UTxO per
block — so users cannot all hit the pool directly. Instead a user locks an
**order** (an intent: "swap X for at least Y") at an order script, and an
off-chain agent — the **batcher** — collects many orders and executes them
against the pool in a single transaction *that the batcher signs*. The
consequence for identity gating is structural: **the trader never signs the
executing transaction**, so the gate must verify a trader signature carried
*inside the order*, not the transaction's signature list. This single fact
reshapes the whole [DeFi case design](design/business-cases/regulated-defi.md).

### Aggregator and composability

An **aggregator** routes one trade through several pools/venues for a better
price. **Composability** is the general property that DeFi contracts can be
freely combined. Identity-gated pools break both by default — an ungated
aggregator cannot route through a gated pool — which fragments liquidity: the
economic failure mode of the gated-pool precedent.

### MEV

**Maximal extractable value**: profit whoever orders transactions (block
producers, batchers) can extract by sequencing, inserting, or censoring them —
e.g. front-running a large pending order. Background reading:
https://ethereum.org/en/developers/docs/mev/ — it appears in these docs
because attributed order flow makes MEV *worse*: front-running "a wallet" is a
statistic, front-running "a named bank's order flow" is a targeted strategy.

### Allowlist

The incumbent gating pattern: an operator-maintained list of approved
addresses that a contract consults. Simple, and the precedent (Aave Arc, a
permissioned pool whitelisted by Fireblocks) saw little uptake. Its three
structural weaknesses — trusted operator, non-portable identity, operational
revocation — are the antithesis this whole project argues against; see
[The Regulated DeFi Gate](design/defi-gate.md).

---

## Institutional actors — who the "users" actually are

### Fund, desk, treasury

The recurring buyers in the case studies. A **fund** invests pooled client
money under a mandate. A bank **desk** is a unit trading a specific market. A
**corporate treasury** manages a company's own cash and must follow board-set
policy ("only stake with identified operators" is exactly such a policy).
None of these can transact with anonymous counterparties and stay inside
their rules — that is the entire demand thesis.

### Officer, and why OOR credentials matter

Companies act through people. An **officer** (CEO, CFO, treasurer) is someone
legally empowered to bind the company — and counterparties need proof of that
authority, traditionally a certified board resolution. The vLEI **OOR
credential** (Official Organizational Role) is that proof in cryptographic
form; **ECR** (Engagement Context Role) is the narrower "authorized for this
specific engagement" variant. This is why the case studies insist the *acting*
credential is the role credential — the fourth hop in the chain — and never
the entity's root key.

### Omnibus position

One account held by an intermediary (a broker) that commingles many end
clients, whose individual holdings appear only in the broker's private books.
The traditional workaround for retail access — and the one that gives up
exactly the transparency an on-chain register promises, which is why the
security-tokens case treats it as a pitch-weakening fallback rather than a
solution.
