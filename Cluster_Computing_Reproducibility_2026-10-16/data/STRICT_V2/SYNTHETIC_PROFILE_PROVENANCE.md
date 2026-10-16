# Synthetic profile provenance and calibration boundary

## What the local code supports

The frozen Hardware_Profile_Data.m defines three node archetypes, three DNN workload rows, and six execution-time rows. Its comments call the values empirical and name Raspberry Pi 4B, Jetson Nano, and a cloud server, but the reproducibility package contains no raw timing observations, benchmark command, device configuration, measurement date, repeated-run distribution, or source citation tied to those numeric values. Those comments overstate provenance and have been corrected in the isolated candidate to label the numbers synthetic.

| Profile | Nominal capacity tuple in the code | Model-time constants (seconds; MobileNetV2 / ResNet50 / VGG16) |
|---|---:|---:|
| Pi-like | 1.0, 4 cores, 2 GB | 0.150 / 1.200 / 4.500 |
| Nano-like | 5.0, 4 cores, 5 GB | 0.030 / 0.200 / 0.800 |
| Server-like | 50.0, 64 cores, 100 GB | 0.001 / 0.005 / 0.020 |

The paired workload metadata are respectively (input MB, weights MB, GFLOPs): MobileNetV2 (1.5, 14, 0.6), ResNet50 (3, 98, 3.8), VGG16 (10, 528, 15.5). Other three timing rows in the six-row array are placeholders/secondary values and are not the three primary DNN rows described in the manuscript.

## Limited internal consistency check

The primary timing values have a broadly consistent qualitative ordering: server-like is fastest, Nano-like is intermediate, and Pi-like is slowest. Within each archetype, the execution-time ratios are broadly similar across the three DNNs. This is a constructed scale relation, not an empirical calibration. Nominal GHz/core/memory metadata do not mathematically derive the timing table, and the network-rate constants also lack trace provenance. The simulator's later effective GFLOP/s computation is another modeling layer; it does not establish that these profiles represent physical hardware.

## Honest disposition

No external calibration source can be recovered from this local package, so none is invented. A defensible manuscript should call these synthetic profile parameters and restrict claims to simulator sensitivity. To claim device calibration, authors must provide the actual devices and software versions, model/runtime implementations, warm-up and repetition protocol, raw per-inference measurements, summary distributions, and a documented mapping from those measurements to every timing constant. Until supplied, profile-source/calibration remains an author evidence gap and the corrected experiments cannot be called device-validated.
