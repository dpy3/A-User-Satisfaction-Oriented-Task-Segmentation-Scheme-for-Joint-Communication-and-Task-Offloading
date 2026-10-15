# Paper 1 citation verification record

Scope: the 37 citation keys reachable from `paper1_cluster_computing.tex`
through its active `\input{...}` files were audited on 2026-08-04.  The
audit checked title, first author, venue, publication year and DOI against
the Crossref work record.  `Li2018` was checked against the official USENIX
NSDI proceedings because it has no Crossref DOI record.  A citation was
retained only where the manuscript's use was supported by the verified work.

## Outcome

- **26 active entries retained:** 25 have a verified DOI and one is the
  USENIX-proceedings Edgent paper.
- **11 active entries removed:** their bibliography metadata could not be
  matched reliably enough to support the manuscript's claim, and each was a
  non-essential generic related-work citation.
- **11 previously unused entries removed:** no uncited bibliography material
  remains.
- The current active citation set has no missing keys and no unused entries.

## Retained evidence

| Citation key | External identifier | Verification result |
|---|---|---|
| `Mao2017` | `10.1109/COMST.2017.2745201` | Exact title, authors, journal, year and pages matched. |
| `Shi2016` | `10.1109/JIOT.2016.2579198` | Exact metadata matched. |
| `Mach2017` | `10.1109/COMST.2017.2682318` | Exact metadata matched. |
| `Abbas2018` | `10.1109/JIOT.2017.2750180` | Exact metadata matched. |
| `Kumari2022` | `10.1016/j.comnet.2022.109137` | Exact metadata matched. |
| `Zhou2019` | `10.1109/JPROC.2019.2918951` | Exact title/authors/year matched; pages corrected to 1738--1762. |
| `Chen2018` | `10.1109/JSAC.2018.2815360` | Exact work matched; author list corrected to Chen and Hao. |
| `You2017` | `10.1109/TWC.2016.2633522` | Exact metadata matched. |
| `Liu2016` | `10.1109/ISIT.2016.7541539` | Exact metadata matched. |
| `Bi2018` | `10.1109/TWC.2018.2821664` | Exact metadata matched. |
| `Zhang2016` | `10.1109/ACCESS.2016.2597169` | Exact work matched; year/volume/pages corrected from the former `Zhang2018` record. |
| `Meng2019` | `10.1109/TWC.2019.2926465` | Verified replacement for the former incorrect `Wang2020` record. |
| `Kang2017` | `10.1145/3093336.3037698` | Exact metadata matched. |
| `Li2018` | USENIX NSDI 2018 proceedings | Title corrected to *Edgent: On-Demand DNN Co-Inference with Device-Edge Synergy*. |
| `Eshratifar2019` | `10.1109/ISLPED.2019.8824955` | Title and second author corrected from Crossref. |
| `Teerapittayanon2017` | `10.1109/ICDCS.2017.226` | Exact metadata matched. |
| `Hu2019DNNsurgery` | `10.1109/INFOCOM.2019.8737614` | Exact metadata matched. |
| `Mnih2015` | `10.1038/nature14236` | Exact metadata matched. |
| `Huang2020` | `10.1109/TMC.2019.2928811` | Exact work matched; issue year corrected from 2019 to 2020. |
| `Tang2022` | `10.1109/TMC.2020.3036871` | Exact work matched; issue year corrected from 2020 to 2022. |
| `Min2019` | `10.1109/TVT.2018.2890685` | Venue, volume, issue and pages corrected. |
| `Deng2020` | `10.1109/JIOT.2020.2984887` | Exact metadata matched. |
| `Sun2016` | `10.1109/MCOM.2016.1600492CM` | Exact metadata matched. |
| `Premsankar2018` | `10.1109/JIOT.2018.2805263` | Exact metadata matched. |
| `Samy2022` | `10.1109/TNSM.2022.3190493` | Verified security-offloading replacement for the former incorrect `Li2022` record. |
| `Deng2021` | `10.1109/JIOT.2021.3057694` | Verified user-centric-offloading replacement for the former incorrect `Wang2021` record. |

## Removed active entries

`Liu2019`, `Liu2021`, `Liu2020`, `Qian2019`, `Ren2019`, `Yang2020`,
`Wu2021`, `Wu2022`, `Xu2022`, `Zhang2021`, and `Zhou2021` were cited in
generic related-work sentences.  The records were removed rather than
guessed because at least one of title, author list, venue, year, page range,
or DOI could not be reconciled with the queried public metadata.  The text
was narrowed so that no removed citation is needed to substantiate it.

## Removed unused entries

`Bao2019`, `Chen2019`, `Li2023`, `Liu2024`, `Wang2022`, `Zhang2022`,
`Zhao2023`, `Zhou2022`, `Zhu2017`, `mao2016energy`, and
`mao2016resource` were present in the old BibTeX file but had no citation in
the compiled manuscript.  They were deleted instead of being retained as
unverified padding.

## Reproducibility note

This record confirms bibliographic identity and the conservative claim-to-
citation linkage used in the related-work section.  It does not treat cited
papers as evidence for this manuscript's numerical results; those claims are
supported only by the frozen run-level CSV files named in the claim-evidence
audit.
