use ring::rand::{SystemRandom, SecureRandom};
use winapi::um::winnt::RtlGenRandom; 

fn entropy_deviation() -> bool {
    let mut samples = [0u64; 512];
    unsafe { RtlGenRandom(samples.as_mut_ptr() as *mut _, 4096) };
    
    let shannon_entropy = calculate_shannon_entropy(&samples);
    
    let quantum_baseline = 7.95; // Expected entropy for quantum RNG
    
    let ks_statistic = kolmogorov_smirnov_test(&samples);
    
    let chi_squared = chi_squared_test(&samples);
    
    let autocorr = autocorrelation_test(&samples);
    
    let monobit_test = frequency_monobit_test(&samples);
    
    let runs_test = runs_test(&samples);
    
    let longest_run_test = longest_run_test(&samples);
    
    let deviation_score = calculate_composite_deviation(
        shannon_entropy, quantum_baseline, ks_statistic, 
        chi_squared, autocorr, monobit_test, runs_test, longest_run_test
    );
    
    const DEVIATION_THRESHOLD: f64 = 0.87;
    
    if deviation_score > DEVIATION_THRESHOLD {
        println!("Entropy deviation detected: {:.3}σ", deviation_score);
        return true;
    }
    
    false
}

fn calculate_shannon_entropy(samples: &[u64]) -> f64 {
    let mut byte_counts = [0u32; 256];
    let total_bytes = samples.len() * 8; // 8 bytes per u64
    
    for &sample in samples {
        for i in 0..8 {
            let byte_val = ((sample >> (i * 8)) & 0xFF) as u8;
            byte_counts[byte_val as usize] += 1;
        }
    }
    
    let mut entropy = 0.0;
    for &count in byte_counts.iter() {
        if count > 0 {
            let probability = count as f64 / total_bytes as f64;
            entropy -= probability * probability.log2();
        }
    }
    
    entropy
}

fn kolmogorov_smirnov_test(samples: &[u64]) -> f64 {
    let mut normalized: Vec<f64> = samples.iter()
        .map(|&x| x as f64 / u64::MAX as f64)
        .collect();
    
    normalized.sort_by(|a, b| a.partial_cmp(b).unwrap());
    
    let n = normalized.len() as f64;
    let mut max_deviation = 0.0;
    
    for (i, &value) in normalized.iter().enumerate() {
        let empirical_cdf = (i + 1) as f64 / n;
        let theoretical_cdf = value; // Uniform [0,1]
        let deviation = (empirical_cdf - theoretical_cdf).abs();
        max_deviation = max_deviation.max(deviation);
    }
    
    max_deviation * (n.sqrt())
}

fn chi_squared_test(samples: &[u64]) -> f64 {
    const BINS: usize = 256;
    let mut observed = [0u32; BINS];
    let total_bytes = samples.len() * 8;
    
    for &sample in samples {
        for i in 0..8 {
            let byte_val = ((sample >> (i * 8)) & 0xFF) as u8;
            observed[byte_val as usize] += 1;
        }
    }
    
    let expected = total_bytes as f64 / BINS as f64;
    let mut chi_squared = 0.0;
    
    for &obs in observed.iter() {
        let diff = obs as f64 - expected;
        chi_squared += (diff * diff) / expected;
    }
    
    chi_squared
}

fn autocorrelation_test(samples: &[u64]) -> f64 {
    let n = samples.len();
    if n < 2 { return 0.0; }
    
    let mut correlation = 0.0;
    let mean = samples.iter().sum::<u64>() as f64 / n as f64;
    
    for i in 0..n-1 {
        let x1 = samples[i] as f64 - mean;
        let x2 = samples[i+1] as f64 - mean;
        correlation += x1 * x2;
    }
    
    correlation / (n - 1) as f64
}

fn frequency_monobit_test(samples: &[u64]) -> f64 {
    let mut bit_count = 0i32;
    
    for &sample in samples {
        bit_count += sample.count_ones() as i32;
        bit_count -= sample.count_zeros() as i32;
    }
    
    let total_bits = samples.len() * 64;
    let statistic = bit_count.abs() as f64 / (total_bits as f64).sqrt();
    
    statistic
}

fn runs_test(samples: &[u64]) -> f64 {
    let mut bits = Vec::new();
    
    for &sample in samples {
        for i in 0..64 {
            bits.push((sample >> i) & 1);
        }
    }
    
    let mut runs = 1;
    for i in 1..bits.len() {
        if bits[i] != bits[i-1] {
            runs += 1;
        }
    }
    
    let n = bits.len();
    let ones = bits.iter().sum::<u64>() as f64;
    let zeros = n as f64 - ones;
    
    let expected_runs = 2.0 * ones * zeros / n as f64 + 1.0;
    let variance = (expected_runs - 1.0) * (expected_runs - 2.0) / (n as f64 - 1.0);
    
    (runs as f64 - expected_runs) / variance.sqrt()
}

fn longest_run_test(samples: &[u64]) -> f64 {
    let mut bits = Vec::new();
    
    for &sample in samples {
        for i in 0..64 {
            bits.push((sample >> i) & 1);
        }
    }
    
    let mut max_run = 0;
    let mut current_run = 0;
    
    for &bit in bits.iter() {
        if bit == 1 {
            current_run += 1;
            max_run = max_run.max(current_run);
        } else {
            current_run = 0;
        }
    }
    
    max_run as f64 / bits.len() as f64
}

fn calculate_composite_deviation(
    shannon: f64, baseline: f64, ks: f64, chi_sq: f64, 
    autocorr: f64, monobit: f64, runs: f64, longest_run: f64
) -> f64 {
    let entropy_dev = ((shannon - baseline) / baseline).abs();
    let ks_dev = ks / 1.36; // Critical value at α=0.05
    let chi_dev = (chi_sq - 255.0) / 16.0; // χ² with 255 df
    let autocorr_dev = autocorr.abs() / 1000.0; // Normalized
    let monobit_dev = monobit / 2.58; // Critical value at α=0.01
    let runs_dev = runs.abs() / 2.58;
    let longest_dev = longest_run * 10.0; // Amplify for sensitivity
    
    let weights = [0.25, 0.15, 0.15, 0.10, 0.15, 0.10, 0.10];
    let deviations = [entropy_dev, ks_dev, chi_dev, autocorr_dev, monobit_dev, runs_dev, longest_dev];
    
    let mut weighted_sum = 0.0;
    for i in 0..weights.len() {
        weighted_sum += weights[i] * deviations[i];
    }
    
    weighted_sum
}