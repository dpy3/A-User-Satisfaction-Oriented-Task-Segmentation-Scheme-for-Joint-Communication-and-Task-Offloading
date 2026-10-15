function [Fog, meta] = MCA_Apply_Infrastructure_Profile(Fog, profile_name)
% Apply a frozen resource-composition intervention without changing topology.
name = lower(char(string(profile_name)));
meta = struct('Name', string(name), 'ComputeScale', 1.0, ...
    'MemoryScale', 1.0, 'BandwidthScale', 1.0, 'Description', "");

switch name
    case 'balanced'
        meta.Description = "Original 2 Nano + 2 Pi + 1 cloud composition";
    case 'compute_bound'
        meta.ComputeScale = 0.15;
        meta.MemoryScale = 2.0;
        meta.Description = "Compute-bound composition with memory headroom";
    case 'memory_bound'
        meta.MemoryScale = 0.35;
        meta.Description = "Memory-bound composition with unchanged compute and links";
    case 'latency_filtered'
        meta.BandwidthScale = 0.005;
        meta.Description = "Latency-filtered composition with restricted type-node feasibility";
    case 'latency_comm_v2'
        % Frozen by Calibrate_MCA_Latency_Comm_Profile_v2 on runs 71--75.
        meta.BandwidthScale = 0.0008;
        meta.Description = "Versioned communication-bound composition with a discriminable bandwidth intervention";
    case 'latency_comm_isolated_v1'
        % Frozen by Calibrate_MCA_Latency_Comm_Isolated_Profile on runs 111--115.
        meta.MemoryScale = 2.0;
        meta.BandwidthScale = 0.0008;
        meta.Description = "Communication-bound composition with explicit memory headroom";
    case 'latency_comm_isolated_v2'
        % Frozen from structural probes on runs 141--145.
        meta.ComputeScale = 1.5;
        meta.MemoryScale = 2.0;
        meta.BandwidthScale = 0.0007;
        meta.Description = "Communication-bound composition with compute and memory headroom";
    case 'latency_comm_isolated_v3'
        % Final profile candidate: stable-capacity bandwidth with resource headroom.
        meta.ComputeScale = 1.5;
        meta.MemoryScale = 2.0;
        meta.BandwidthScale = 0.001;
        meta.Description = "Communication-bound profile calibrated on slot-level discriminability";
    case 'edge_rich'
        assert(size(Fog, 1) == 5, 'MCA:ProfileTopology', ...
            'edge_rich is frozen for the five-node topology.');
        % Replace one Pi-class node by a Nano-class node; retain one cloud.
        Fog(3, 4) = 100;
        Fog(3, 7) = 100;
        Fog(3, 6) = 500e6;
        Fog(3, 8) = 4096;
        meta.Description = "3 Nano + 1 Pi + 1 cloud composition";
    otherwise
        error('MCA:UnknownInfrastructureProfile', 'Unknown infrastructure profile: %s', name);
end

Fog(:, 4) = Fog(:, 4) * meta.ComputeScale;
Fog(:, 7) = Fog(:, 7) * meta.ComputeScale;
Fog(:, 6) = Fog(:, 6) * meta.BandwidthScale;
Fog(:, 8) = Fog(:, 8) * meta.MemoryScale;
meta.TotalCompute = sum(Fog(:, 4));
meta.TotalMemoryMB = sum(Fog(:, 8));
meta.TotalBandwidthMbps = sum(Fog(:, 6)) / 1e6;
end
