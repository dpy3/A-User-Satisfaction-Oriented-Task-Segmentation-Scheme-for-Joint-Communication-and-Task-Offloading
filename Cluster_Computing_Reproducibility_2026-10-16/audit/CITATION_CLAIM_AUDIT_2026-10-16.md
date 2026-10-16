# Citation and claim audit (2026-10-16)

## Scope and evidence

The bibliography contains 28 entries; all 28 keys are cited and every in-text key resolves to a bibliography entry. The DOI/title/author/year/venue fields were checked against the saved Crossref audit and retrieved OpenAlex work records. OpenAlex returned a record for all 28 references and an abstract for 26. The abstracts were used to check the scoped descriptions below; the original full text was not available for every item, so this is not a sentence-by-sentence full-text review. For the two records without an OpenAlex abstract (Kumari et al. and Mnih et al.), the manuscript has been kept at survey/title-level scope or the publisher's article description was consulted for the DQN historical example.

The source records are preserved in `citation_audit_final/OPENALEX_BIBLIOGRAPHY_EVIDENCE.json`. Bibliographic identity checks and claim-content checks are separate: metadata agreement alone is not treated as proof of a claim.

## Claim-to-source map

| Reference | Manuscript characterization checked | Evidence and disposition |
|---|---|---|
| Mao et al. (2017) | MEC architecture and computation offloading survey | Abstract describes MEC placement at network edges and surveys joint radio/computational resource management; supported at the stated scope. |
| Shi et al. (2016) | Edge computing places processing near the network edge | Abstract defines edge computing around processing data at the edge and discusses response-time and bandwidth concerns; supported. |
| Mach and Becvar (2017) | MEC architecture and computation-offloading survey | Title and abstract identify the survey scope; supported. |
| Abbas et al. (2018) | MEC survey | Title and abstract identify MEC architecture and use cases; supported. |
| Kumari et al. (2022) | Survey of fog task-offloading algorithms and optimization techniques | OpenAlex abstract unavailable; title, DOI, and Crossref metadata support only this narrow survey characterization. No detailed finding is attributed to it. |
| Zhou et al. (2019) | Edge-intelligence review | Abstract describes edge intelligence and its AI/edge-computing scope; supported. |
| Chen and Hao (2018) | Task offloading in software-defined ultra-dense networks | Abstract identifies the network setting and delay/energy objective; supported. |
| You et al. (2017) | Energy-aware resource allocation for multi-user MEC offloading | Abstract describes multi-user resource allocation and energy minimization; supported. |
| Liu et al. (2016) | Delay-oriented MEC task scheduling | Abstract describes a two-timescale scheduling/offloading problem and MDP approach; supported. |
| Bi and Zhang (2018) | Binary offloading in wireless-powered MEC | Abstract explicitly describes binary offloading in a wireless-powered multi-user MEC system; supported. |
| Zhang et al. (2016) | Energy-efficient offloading in heterogeneous 5G networks | Abstract supports the energy objective and joint offloading/radio allocation. The manuscript no longer labels this work as a binary-decision model. |
| Meng et al. (2019) | Queue-aware, delay-oriented MEC offloading | Abstract describes coupled mobile/server queues, a long-term MDP formulation, and an approximate multi-level water-filling solution. The unsupported “partial offloading” label was removed. |
| Kang et al. (2017), Neurosurgeon | DNN partitioned execution between mobile devices and cloud | Publisher article description and abstract-level indexing support collaborative cloud/mobile inference; supported at this scope. |
| Li et al. (2018), Edgent | Device-edge DNN partitioning and early exit | Abstract explicitly describes adaptive partitioning and right-sizing via early exit; supported. |
| Eshratifar et al. (2019), BottleNet | Intermediate-feature compression for mobile-cloud inference | Abstract explicitly describes feature compression and accuracy compensation; supported. |
| Teerapittayanon et al. (2017) | Distributed DNN execution across cloud, edge, and devices | Abstract describes a distributed DNN hierarchy and mapping network sections across tiers; supported. |
| Hu et al. (2019) | Adaptive DNN partitioning under network dynamics | Abstract identifies DNN surgery, edge/cloud partitioning, and network dynamics; supported. |
| Mnih et al. (2015) | Historical DQN/DRL example, explicitly distinguished from MEC scheduling | Publisher description identifies Atari-game control; the revised text explicitly says this is not MEC evidence. Supported as background only. |
| Huang et al. (2020) | Online DRL for wireless-powered MEC offloading | Abstract identifies binary offloading, time-varying wireless conditions, and online resource allocation; supported. |
| Tang and Wong (2022) | Model-free DRL for decentralized MEC task offloading | Abstract describes non-divisible delay-sensitive tasks, uncertain edge load, and a distributed model-free DRL method; supported. |
| Min et al. (2019) | RL-based edge selection/offloading rate under energy harvesting | Abstract describes RL and deep-RL policies using battery, link, and harvested-energy information. The unsupported “binary offloading” label was removed. |
| Deng et al. (2020) | Edge-intelligence overview | Abstract describes AI for edge and AI on edge; supported as a broad overview. |
| Sun and Ansari (2016) | EdgeIoT architecture | Abstract describes local fog nodes and an SDN-based hierarchy; supported. |
| Premsankar et al. (2018) | Edge computing for IoT and case-study evaluation | Title and abstract identify the survey/case-study scope; supported. |
| Samy et al. (2022) | Security-aware blockchain MEC offloading with DRL | Abstract identifies blockchain-enabled secure task offloading and DRL; supported. |
| Deng et al. (2021) | User-centric edge computation offloading | Title and abstract identify user-delay and edge-offloading decisions; supported. |
| Pan et al. (2024) | Joint server/service deployment in multi-layer C-RAN/MEC | Abstract describes joint deployment across communities and cooperating edge servers; supported. |
| Yang et al. (2024) | User-satisfaction-based C-RAN/MEC task offloading | Abstract explicitly describes a user-satisfaction-maximizing offloading model; supported. |

## Revisions made to remove overstatement

- Removed the broad, uncited generalization that “much of the literature” is slot-local and primarily optimizes energy or average delay; the revised paragraph names the different objectives represented by the cited studies and avoids claiming a systematic review.
- Removed the unsupported binary-offloading label for Zhang et al. (2016) and Min et al. (2019).
- Removed the unsupported partial-offloading label for Meng et al. (2019); its queue-aware, delay-oriented MDP characterization is used instead.
- Distinguished Mnih et al.'s Atari control result from MEC scheduling and explicitly stated that this paper does not compare against or validate a DRL scheduler.
- Narrowed DNN-system descriptions to what the cited work actually studies: mobile/cloud partitioning, device/edge partitioning with early exits, and mobile/cloud feature compression.
- Removed the citation that implied Mao et al. directly supports this paper's simulator-specific context-switching mechanism; that statement is now identified as part of the implemented model.

## Remaining evidence boundary

All 28 cited items have identity metadata; two abstract records were unavailable through OpenAlex. Claims are limited to the article titles, publisher descriptions, and abstracts retrieved in this audit. A journal-required exhaustive novelty review or claims that depend on full-text details would still require full-text review by the authors.
