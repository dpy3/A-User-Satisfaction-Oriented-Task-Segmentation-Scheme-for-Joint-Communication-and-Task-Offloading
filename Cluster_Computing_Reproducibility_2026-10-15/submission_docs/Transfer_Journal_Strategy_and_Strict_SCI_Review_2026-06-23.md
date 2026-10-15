# Transfer Journal Strategy and Strict SCI Review

Date: 2026-06-23

## Bottom-line verdict

This manuscript is not currently positioned like a top systems or top networking paper. Its strongest asset is not raw method novelty, but the combination of:

1. a reasonably clear fog-offloading problem setting,
2. a stronger-than-average evaluation pipeline,
3. a useful systems interpretation of backlog-sensitive scheduling.

Under a strict SCI standard, this makes it more suitable for a solid edge/cloud/network systems journal than for a top-tier flagship venue.

## Recommended transfer targets

### 1. First recommendation: Cluster Computing

Why it fits:
- Broad scope across distributed computing systems, computer networks, and application-oriented systems work.
- Official page explicitly positions the journal around parallel and distributed computing, computer networks, and HPDC-style environments.
- The journal currently reports Journal Impact Factor 4.1 (2024) and median submission-to-first-decision 25 days.

Why this paper fits there:
- The manuscript is simulator-heavy and benchmark-heavy.
- The method is a hybrid/meta-heuristic controller, which matches the style of many papers that appear in this venue.
- The contribution is a systems-and-evaluation package, not only a new theorem or architecture.

### 2. Second recommendation: Journal of Cloud Computing

Why it fits:
- Official scope covers cloud computing alongside wider paradigms, including edge-related topics.
- The journal currently reports Journal Impact Factor 4.3 (2024) and median submission-to-first-decision 40 days.

Why this paper fits there:
- The paper already frames itself as a cloud/edge/fog scheduling problem.
- The service-oriented evaluation story is stronger than the bare algorithm story, and this venue is more tolerant of framework-plus-method papers than a pure networking flagship.

Main caution:
- This journal is open access, so APC/funding needs to be considered.

### 3. Conservative fallback: Wireless Networks

Why it fits:
- Official scope covers wireless/mobile communication, computation, and information, with emphasis on networking and user aspects.
- The journal currently reports Journal Impact Factor 2.5 (2025) and median submission-to-first-decision 14 days.

Why this paper fits there:
- The current manuscript includes channel models, wireless-side assumptions, and repeated service behavior under congestion.
- If fast review and a more realistic acceptance path matter, this is safer than forcing the paper into a stronger systems venue.

Main caution:
- The paper should keep enough networking flavor. If the optimization language dominates too much, the fit weakens.

## Venues not recommended for immediate resubmission

### Future Generation Computer Systems
Not the right immediate target unless the paper is substantially upgraded.

Reason:
- Official metrics are substantially stronger.
- Reviewers there are more likely to ask for either deeper methodological novelty or more convincing real-system evidence.
- In its current state, this manuscript still looks more like a strong simulation-and-evaluation paper than a field-shaping systems contribution.

### IEEE Internet of Things Journal / Computer Networks / similarly stronger venues
Not recommended for immediate transfer.

Reason:
- The manuscript still carries too much simulation dependence.
- The strongest claim is conditional and benchmark-bounded.
- The algorithmic novelty is incremental-combinational rather than clearly foundational.

## Strict SCI-style harsh review

### What likely got the paper rejected

1. **Method novelty is not strong enough for a demanding venue.**
   M-CA-ALM is presented as a hybrid of memetic search, augmented-Lagrangian refinement, congestion-aware gradients, and repair. That is publishable, but it reads more like a well-engineered combination than a sharp conceptual leap.

2. **The paper's strongest contribution is actually the evaluation protocol, but the title and framing previously over-emphasized the optimizer.**
   This creates reviewer friction. Reviewers ask: is this a new optimization algorithm, or is it a new evaluation lens? If the answer is "both", then each side is judged by the stricter standard of the other.

3. **Evidence is still dominated by trace-driven simulation.**
   The paper openly admits that the benchmark is not a fully deployed live system. For higher bars, that immediately caps enthusiasm.

4. **The strongest result is conditional, not global.**
   The paper itself now correctly says the gain is regime-dependent and may shrink under budget matching. That is intellectually honest, but it also means the method does not deliver a clean "dominates strong baselines" story.

5. **The bibliography contained suspicious recent references.**
   Even if they were only used for framing, this damages reviewer trust.

### Harsh but fair scorecard

- Problem relevance: **8/10**
- Method novelty: **5.5/10**
- Experimental breadth: **8/10**
- Experimental credibility: **6.5/10**
- Real-system grounding: **5/10**
- Writing maturity after revision: **7.5/10**
- Target-venue ambition realism: **too high before revision**

## Concrete revision strategy for transfer

### Must do before resubmission

1. **Retarget the paper's identity**
   Present it as:
   - a service-oriented fog-scheduler evaluation paper, plus
   - a congestion-aware controller that performs well under that stricter protocol.

   Do not present it as a universally strong new optimizer.

2. **Clean the bibliography**
   Remove, replace, or verify suspicious entries before submission.

3. **Tighten claims around baseline superiority**
   Keep only conditional, benchmark-bounded, evidence-traceable claims.

4. **Preserve the stronger parts**
   The exact-reference bridge, long-horizon replay, and robustness sections are the manuscript's best defense. Do not compress them away.

### Nice to have, if time allows

1. Add one compact table comparing:
   - novelty type,
   - experimental realism,
   - strongest limitation,
   - claimed deployment scope.

2. Add a short reproducibility paragraph pointing to scripts and result generation order.

3. If possible, add one small real-device closed-loop sanity experiment, even if narrow.

## Fast edits already applied in this transfer pass

1. The title was retargeted to foreground both evaluation and optimization rather than pretending the paper is only an optimizer paper.
2. The abstract was softened to emphasize the bounded contribution and the service-oriented evaluation message.
3. The introduction now states more clearly that the paper is both an optimization study and an evaluation study.
4. The conclusion now explicitly reinforces the evaluation contribution as a first-class contribution.

## Recommended submission order

1. Cluster Computing
2. Journal of Cloud Computing
3. Wireless Networks

If fast acceptance probability matters more than prestige, switch 2 and 3 depending on APC tolerance and desired review speed.
