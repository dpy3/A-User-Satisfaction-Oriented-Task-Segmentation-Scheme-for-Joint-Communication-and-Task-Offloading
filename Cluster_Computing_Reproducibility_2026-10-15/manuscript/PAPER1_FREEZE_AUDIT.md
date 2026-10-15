# Paper 1 Freeze Audit

## Story and paragraph roles

- Abstract: challenge, mechanism, strongest static and replay evidence, negative boundary.
- Introduction: task, raw-versus-repaired mismatch, outcome-aligned mechanism,
  contributions, bounded claim.
- Discussion: causal attribution within the factorial design, regime dependence,
  runtime cost, dynamic boundary, limitations.
- Conclusion: mechanism, static evidence, ablation evidence, replay evidence,
  held-out boundary, explicit non-claims and remaining evidence gates.

## Claim-evidence map

| Claim | Evidence | Status |
| --- | --- | --- |
| Raw scoring is misaligned with the deployed repaired schedule. | Raw/final assignment-agreement audit and shared final repair protocol. | Supported within the implemented pipeline. |
| Repair-aware ranking produces the confirmed ALM gain. | 30-seed paired 2x2 ablation: Repair-aware equals Full; Raw equals Guard. | Supported; guarded acceptance is not claimed as a gain-producing component. |
| M-CA-ALM improves satisfaction in static recoverable congestion. | Table II, six paired congested scales, confidence intervals, effect sizes, Holm tests. | Supported for the fixed five-node benchmark. |
| M-CA-ALM improves replay persistence at N=180. | Twenty paired 500-slot runs, satisfaction, first-full-backlog slot, queue drops. | Supported at the reported replay setting. |
| The benefit does not extend to immediate saturation. | N=300 replay and independent v9 runs 31-50. | Supported negative operating boundary. |
| Repair-aware ranking transfers beyond ALM. | Frozen GA/ALM four-arm experiment on independent runs 31-50. | Supported in the independently tested GA family. |
| The comparison includes a modern learned optimizer. | OfflineGNN trained on runs 51-55, selected on 61-63, tested on official runs 1-30. | Supported as one leakage-free internally trained comparator, not a published method. |
| Results generalize across infrastructures or establish deployment stability. | No qualifying evidence in Paper 1. | Not claimed. |

## Five-dimension adversarial review

1. Contribution: pass for the bounded outcome-alignment insight; do not add a
   capacity, admission, or infrastructure contribution.
2. Writing clarity: pass after terminology and scope cleanup; the same fixed
   five-node and repaired-outcome semantics are used across major sections.
3. Experimental strength: pass for paired static, ablation, replay, held-out,
   and negative-boundary evidence; runtime cost remains explicit.
4. Evaluation completeness: formal repair transfer and one leakage-free learned
   comparator are complete; cross-infrastructure and deployment evidence remain out of scope.
5. Method soundness: pass within the simulator; the current evidence does not
   support arbitrary overload, online stability, or live deployment.

## Freeze decision

The independent GA gate in `REPAIR_TRANSFER_PROTOCOL.md` passed. The manuscript
may state transfer to the tested GA family, but not to arbitrary optimizers or
repair operators. No outcome of this gate authorizes a new research question.
