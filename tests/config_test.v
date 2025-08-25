module tests

import os
import glo55

// Simple test implementation of ConfigTarget for testing
struct TestConfigTarget {
mut:
	// ConfigTarget properties
	border_width        int               = 2
	gap_size            int               = 10
	focus_follows_mouse bool              = true
	theme_name          string            = 'default'
	keybindings         map[string]string
	workspace_names     []string          = ['1', '2', '3', '4', '5']
}

// Test loading valid TOML files
fn test_config_load_valid_toml() {
	// Create a temporary valid config file
	test_content := '
border_width = 5
gap_size = 15
focus_follows_mouse = false
theme_name = "dark"
'

	test_file := '/tmp/glo55_test_config.toml'
	os.write_file(test_file, test_content) or { assert false, 'Failed to write test config file' }
	defer { os.rm(test_file) or {} }

	// Load configuration directly into test target
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert false, 'Failed to load valid config: ${err}'
		return
	}

	// Verify parsed values
	assert target.border_width == 5
	assert target.gap_size == 15
	assert target.focus_follows_mouse == false
	assert target.theme_name == 'dark'
}

// Test error handling for malformed files
fn test_config_load_malformed_toml() {
	// Create a temporary malformed config file
	malformed_content := '
border_width = 
gap_size = "not_a_number"
[unclosed_section
'

	test_file := '/tmp/glo55_test_malformed.toml'
	os.write_file(test_file, malformed_content) or {
		assert false, 'Failed to write test malformed file'
	}
	defer { os.rm(test_file) or {} }

	// Attempt to load malformed file should fail
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		// This should fail - error expected
		assert err.msg().contains('Failed to parse TOML')
		return
	}

	assert false, 'Malformed TOML should have failed to parse'
}

// Test validation of configuration values
fn test_config_validation_errors() {
	// Test invalid border width
	invalid_border_content := 'border_width = -5'
	test_file := '/tmp/glo55_test_invalid_border.toml'
	os.write_file(test_file, invalid_border_content) or {
		assert false, 'Failed to write test file'
	}
	defer { os.rm(test_file) or {} }

	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert err.msg().contains('Invalid border_width')
		assert err.msg().contains('must be between 0 and 50')
		return
	}
	assert false, 'Invalid border_width should have failed validation'

	// Test invalid gap size
	invalid_gap_content := 'gap_size = 150'
	test_file2 := '/tmp/glo55_test_invalid_gap.toml'
	os.write_file(test_file2, invalid_gap_content) or { assert false, 'Failed to write test file' }
	defer { os.rm(test_file2) or {} }

	mut target2 := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target2, test_file2) or {
		assert err.msg().contains('Invalid gap_size')
		assert err.msg().contains('must be between 0 and 100')
		return
	}
	assert false, 'Invalid gap_size should have failed validation'

	// Test empty theme name
	empty_theme_content := 'theme_name = ""'
	test_file3 := '/tmp/glo55_test_empty_theme.toml'
	os.write_file(test_file3, empty_theme_content) or { assert false, 'Failed to write test file' }
	defer { os.rm(test_file3) or {} }

	mut target3 := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target3, test_file3) or {
		assert err.msg().contains('Invalid theme_name')
		assert err.msg().contains('cannot be empty')
		return
	}
	assert false, 'Empty theme_name should have failed validation'
}

// Test file path resolution
fn test_config_file_path_resolution() {
	// Test nonexistent file
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, '/nonexistent/path/config.toml') or {
		assert err.msg().contains('Configuration file not found')
		return
	}
	assert false, 'Nonexistent file should have failed'
}

// Test loading empty config file (should use defaults)
fn test_config_load_empty_file() {
	// Create an empty config file
	test_file := '/tmp/glo55_test_empty.toml'
	os.write_file(test_file, '') or { assert false, 'Failed to write empty test file' }
	defer { os.rm(test_file) or {} }

	// Load configuration from empty file
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert false, 'Failed to load empty config: ${err}'
		return
	}

	// Should keep default values (since empty file doesn't override anything)
	default_target := TestConfigTarget{}
	assert target.border_width == default_target.border_width
	assert target.gap_size == default_target.gap_size
	assert target.focus_follows_mouse == default_target.focus_follows_mouse
	assert target.theme_name == default_target.theme_name
}

// Test partial configuration (some values present, others default)
fn test_config_partial_configuration() {
	// Create a config with only some values
	partial_content := '
border_width = 3
theme_name = "minimal"
'

	test_file := '/tmp/glo55_test_partial.toml'
	os.write_file(test_file, partial_content) or {
		assert false, 'Failed to write test config file'
	}
	defer { os.rm(test_file) or {} }

	// Load configuration from file
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert false, 'Failed to load partial config: ${err}'
		return
	}

	// Verify specified values are loaded and others use defaults
	assert target.border_width == 3
	assert target.theme_name == 'minimal'

	// These should be defaults since not specified
	default_target := TestConfigTarget{}
	assert target.gap_size == default_target.gap_size
	assert target.focus_follows_mouse == default_target.focus_follows_mouse
}

// Test configuration validation after loading
fn test_config_struct_validation() {
	// Test valid configuration
	valid_target := TestConfigTarget{
		border_width:        5
		gap_size:            20
		focus_follows_mouse: true
		theme_name:          'test'
	}
	glo55.validate_config_target(valid_target) or { assert false, 'Valid config should pass validation: ${err}' }

	// Test invalid border width
	invalid_target1 := TestConfigTarget{
		border_width:        -1
		gap_size:            10
		focus_follows_mouse: true
		theme_name:          'test'
	}
	glo55.validate_config_target(invalid_target1) or {
		assert err.msg().contains('Invalid border_width')
		return
	}
	assert false, 'Invalid border_width should fail validation'
}
