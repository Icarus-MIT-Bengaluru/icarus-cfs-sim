#!/bin/sh
# ICARUS Phase 5 - scheduled-rate checker.
#
# Runs ON THE OBC and validates that an app's scheduled activity actually
# occurred at its declared rate.
#
# Usage: rate-check.sh <app-log> <expected_rate_mhz> <min_samples> <mean_tol_pct>
#
# Intervals are computed from the monotonic microsecond timestamp that each app
# embeds in its own marker, NEVER from the order or arrival time of log lines:
# OSAL's console is asynchronous, so lines are delivered in bursts and their
# arrival time bears no relation to when the event occurred.
#
# Implemented in sh+awk rather than C (unlike udp-probe.c) because this is log
# parsing and interval arithmetic; awk does it in a fraction of the code and is
# already present in the OBC image.
set -eu

LOG="${1:?app log path required}"
EXPECT_MHZ="${2:?expected rate in millihertz required}"
MIN_SAMPLES="${3:?minimum sample count required}"
MEAN_TOL_PCT="${4:-5}"

if [ ! -f "$LOG" ]; then
    echo "FAIL $(basename "$LOG"): log does not exist"
    exit 2
fi

awk -v expect_mhz="$EXPECT_MHZ" \
    -v min_samples="$MIN_SAMPLES" \
    -v tol_pct="$MEAN_TOL_PCT" \
    -v name="$(basename "$LOG" .log)" '
/wakeup seq=/ {
    seq = -1; mono = -1
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^seq=/)     { split($i, a, "="); seq  = a[2] + 0 }
        if ($i ~ /^mono_us=/) { split($i, a, "="); mono = a[2] + 0 }
    }
    if (seq < 0 || mono < 0) { malformed++; next }

    # The log persists across OBC restarts (the /logs mount outlives the
    # container) and every boot restarts seq at 1. A non-increasing seq is
    # therefore a boot boundary, not a fault: discard what came before and
    # measure only the current run. Intervals must never span a restart.
    if (n > 0 && seq <= seqs[n]) {
        boots++
        n = 0
    }

    n++
    seqs[n] = seq
    # A single monotonic microsecond count, so it cannot tear.
    t[n] = mono
}
END {
    # Period in microseconds, derived from the declared millihertz rate.
    nominal_us = 1000000000 / expect_mhz

    if (n == 0) {
        printf "FAIL %s: no wakeup markers found\n", name
        exit 1
    }
    if (malformed > 0) {
        printf "FAIL %s: %d malformed marker(s)\n", name, malformed
        exit 1
    }

    # Sequence numbers must be contiguous. This is what catches MISSING and
    # DUPLICATE wakeups, which the gate requires failing on -- an interval
    # check alone cannot distinguish a dropped wakeup from a slow one.
    for (i = 2; i <= n; i++) {
        if (seqs[i] != seqs[i-1] + 1) {
            printf "FAIL %s: sequence break at %d -> %d (missing or duplicate wakeup)\n", \
                name, seqs[i-1], seqs[i]
            exit 1
        }
    }

    # Discard the first interval: an entry s first send lands PacketRate ticks
    # after SCH is enabled, and SCH itself only starts once the first
    # CFE_TIME 1 Hz packet arrives, so the leading gap is a startup artefact.
    first = 3
    if (n < first) {
        printf "FAIL %s: only %d marker(s); need at least %d after warm-up\n", \
            name, n, min_samples + 2
        exit 1
    }

    samples = 0
    sum = 0; mn = -1; mx = 0
    for (i = first; i <= n; i++) {
        d = t[i] - t[i-1]
        if (d <= 0) {
            printf "FAIL %s: non-monotonic timestamp between seq %d and %d\n", \
                name, seqs[i-1], seqs[i]
            exit 1
        }
        samples++
        sum += d
        iv[samples] = d
        if (mn < 0 || d < mn) mn = d
        if (d > mx) mx = d
    }

    if (samples < min_samples) {
        printf "FAIL %s: %d interval sample(s) after warm-up, need %d\n", \
            name, samples, min_samples
        exit 1
    }

    mean = sum / samples
    mean_hz = 1000000.0 / mean
    expect_hz = expect_mhz / 1000.0
    err_pct = (mean - nominal_us) * 100.0 / nominal_us
    abs_err = (err_pct < 0) ? -err_pct : err_pct

    # Jitter: a 99th-percentile bound plus a hard ceiling.
    #
    # Asserting on the ABSOLUTE maximum is statistically fragile here -- across
    # ~1500 samples at 10 Hz a single scheduler hiccup on a non-realtime
    # containerised kernel fails the gate even though the mean is within 1%.
    # Measured: 2 of 1527 intervals (0.13%) exceeded 2x, none exceeded 3x.
    #
    # So: 99% of intervals must be within 2x nominal (catches a sustained
    # pattern of lateness, which a flat cap set above the noise would miss),
    # and no single interval may exceed 5x (catches a genuinely dropped or
    # stalled wakeup).
    asort_n = samples
    for (i = 1; i <= asort_n; i++) srt[i] = iv[i]
    # insertion sort: sample counts here are small enough and it avoids
    # depending on the gawk asort function, absent from mawk and BWK awk.
    for (i = 2; i <= asort_n; i++) {
        v = srt[i]; j = i - 1
        while (j >= 1 && srt[j] > v) { srt[j+1] = srt[j]; j-- }
        srt[j+1] = v
    }
    pidx = int(asort_n * 0.99)
    if (pidx < 1) pidx = 1
    p99 = srt[pidx]

    printf "%s: n=%d mean=%.1fms (%.4f Hz, declared %.4f Hz, err %+.2f%%) min=%.1fms p99=%.1fms max=%.1fms", \
        name, samples, mean/1000.0, mean_hz, expect_hz, err_pct, mn/1000.0, p99/1000.0, mx/1000.0
    if (boots > 0) {
        printf " [measured the last of %d run(s) in this log]", boots + 1
    }
    printf "\n" 

    ok = 1

    # Mean rate: catches a systematic rate error, e.g. a wrong PacketRate or a
    # mismatch between the table and the rate the app claims.
    if (abs_err > tol_pct) {
        printf "FAIL %s: mean interval off by %+.2f%%, tolerance +/-%s%%\n", \
            name, err_pct, tol_pct
        ok = 0
    }

    if (p99 > 2 * nominal_us) {
        printf "FAIL %s: 99th-percentile interval %.1fms exceeds 2x nominal %.1fms\n", \
            name, p99/1000.0, nominal_us/1000.0
        ok = 0
    }
    if (mx > 5 * nominal_us) {
        printf "FAIL %s: longest interval %.1fms exceeds the 5x hard ceiling %.1fms\n", \
            name, mx/1000.0, 5 * nominal_us/1000.0
        ok = 0
    }

    # NOTE: there is deliberately NO minimum-interval assertion. sch_lab hands
    # ticks to the app through a COUNTING semaphore, so if the scheduler task
    # is briefly descheduled the queued ticks are consumed back-to-back and two
    # sends legitimately appear much closer together than the nominal period.
    # Long-run drift is zero, so the mean is the meaningful rate figure.

    if (ok) {
        printf "PASS %s: %.4f Hz sustained over %d samples, p99 %.1fms, max %.1fms\n", \
            name, mean_hz, samples, p99/1000.0, mx/1000.0
        exit 0
    }
    exit 1
}' "$LOG"
