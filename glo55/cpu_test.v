module glo55

// cpu_test.v - parse_cpu_line: the /proc/stat reader behind the $cpu meter.

fn test_parse_cpu_line() {
	// user nice system idle iowait irq softirq steal
	t, i := parse_cpu_line('cpu  100 20 30 40 50 60 70 80') or {
		assert false, 'should parse'
		return
	}
	assert t == 450
	assert i == 90 // idle + iowait
	t2, i2 := parse_cpu_line('cpu  1 2 3 4 5') or {
		assert false, 'should parse'
		return
	}
	assert t2 == 15 && i2 == 9
	// a malformed or foreign line is refused, not guessed at
	if parse_cpu_line('cpu  1 2 3') != none {
		assert false
	}
	if parse_cpu_line('MemTotal: 4096 kB') != none {
		assert false
	}
	// junk in a field reads as 0 rather than a crash
	t3, i3 := parse_cpu_line('cpu  x 2 3 4 5') or {
		assert false, 'should parse'
		return
	}
	assert t3 == 14 && i3 == 9
}
