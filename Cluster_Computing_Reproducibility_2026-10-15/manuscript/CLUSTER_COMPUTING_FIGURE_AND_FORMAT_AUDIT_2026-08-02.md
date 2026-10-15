# Cluster Computing figure and format audit (2026-08-02)

## Target journal

The manuscript is positioned for *Cluster Computing* (Springer Nature), with
the scientific story framed as congestion-aware task offloading and service
evaluation in a heterogeneous fog cluster.

## Figure changes in this revision

- Formal figures were regenerated from frozen CSV evidence only.
- Paper 1 figures now use larger labels, explicit panel titles, a highlighted
  transition regime, and separate visual encoding for the immediate-overload
  boundary.
- Paper 2 figures now use larger labels, explicit conclusion-oriented titles,
  separated legends, and wider panel spacing. Fig. 3 was specifically revised
  to prevent title--legend overlap.
- Every active figure is exported as editable-text PDF and SVG, 600-dpi TIFF,
  and PNG preview.
- Source-data CSV files remain bundled beside the figure outputs.
- The Springer source was rebuilt after removing the duplicate bibliography
  declaration inherited from the class and disabling duplicate PDF anchors.
- The two remaining overfull table paragraphs were removed by tightening only
  table typography (`\small`/`\scriptsize` and column spacing); no scientific
  values or table contents were changed.
- A clean rebuild now reports no `Overfull`, undefined-reference, undefined-
  citation, or BibTeX errors in the active Springer log.

## Submission-format caveat

The canonical Paper 1 source remains an IEEEtran-compatible working source for
reproducibility. The official Springer Nature `sn-jnl` class is now used in the
submission version, which compiles successfully after translating the
IEEE-only appendix entry point. The scientific content, figures, captions,
references, and claim boundaries are aligned to the target journal; remaining
work is limited to author-confirmed declarations and minor layout cleanup.

## Claim boundary

No figure is interpreted as evidence for cross-topology generalization, live
deployment, or online stability. Static, replay, held-out selector, and
transfer experiments remain separate evidence tiers.
