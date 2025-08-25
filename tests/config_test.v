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
	monitor_configs     []glo55.MonitorConfig
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

// Test keybinding configuration loading
fn test_config_load_keybindings() {
	// Create a config with keybindings
	keybindings_content := '
border_width = 3
theme_name = "keybinding_test"

[keybindings]
"Mod+1" = "workspace 1"
"Mod+Shift+Enter" = "exec kitty"
"Alt+Tab" = "focus next"
"Control+Mod+q" = "quit"
'

	test_file := '/tmp/glo55_test_keybindings.toml'
	os.write_file(test_file, keybindings_content) or {
		assert false, 'Failed to write keybindings test file'
	}
	defer { os.rm(test_file) or {} }

	// Load configuration
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert false, 'Failed to load keybindings config: ${err}'
		return
	}

	// Verify keybindings are loaded
	assert target.keybindings['Mod+1'] == 'workspace 1'
	assert target.keybindings['Mod+Shift+Enter'] == 'exec kitty'
	assert target.keybindings['Alt+Tab'] == 'focus next'
	assert target.keybindings['Control+Mod+q'] == 'quit'
	assert target.border_width == 3
	assert target.theme_name == 'keybinding_test'
}

// Test workspace names configuration
fn test_config_load_workspace_names() {
	workspace_content := '
border_width = 4
workspace_names = ["web", "dev", "mail", "music"]
'

	test_file := '/tmp/glo55_test_workspaces.toml'
	os.write_file(test_file, workspace_content) or {
		assert false, 'Failed to write workspace test file'
	}
	defer { os.rm(test_file) or {} }

	// Load configuration
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert false, 'Failed to load workspace config: ${err}'
		return
	}

	// Verify workspace names are loaded
	assert target.workspace_names == ['web', 'dev', 'mail', 'music']
	assert target.border_width == 4
}

// Test monitor configuration loading
fn test_config_load_monitors() {
	monitors_content := '
border_width = 5

[[monitors]]
workspaces = ["main", "side", "background"]

[[monitors]]
workspaces = ["1", "2", "3", "4"]
'

	test_file := '/tmp/glo55_test_monitors.toml'
	os.write_file(test_file, monitors_content) or {
		assert false, 'Failed to write monitors test file'
	}
	defer { os.rm(test_file) or {} }

	// Load configuration
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert false, 'Failed to load monitors config: ${err}'
		return
	}

	// Verify monitors are loaded
	assert target.monitor_configs.len == 2
	assert target.monitor_configs[0].workspaces == ['main', 'side', 'background']
	assert target.monitor_configs[1].workspaces == ['1', '2', '3', '4']
	assert target.border_width == 5
}

// Test comprehensive configuration with all features
fn test_config_load_comprehensive() {
	comprehensive_content := '
border_width = 1
gap_size = 8
focus_follows_mouse = false
theme_name = "comprehensive_test"
workspace_names = ["default", "work", "play"]

[keybindings]
"Mod+Return" = "exec terminal"
"Mod+d" = "launcher"
"Mod+Shift+q" = "close window"

[[monitors]]
workspaces = ["web", "dev", "debug"]

[[monitors]]
workspaces = ["1", "2"]
'

	test_file := '/tmp/glo55_test_comprehensive.toml'
	os.write_file(test_file, comprehensive_content) or {
		assert false, 'Failed to write comprehensive test file'
	}
	defer { os.rm(test_file) or {} }

	// Load configuration
	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert false, 'Failed to load comprehensive config: ${err}'
		return
	}

	// Verify all sections are loaded correctly
	assert target.border_width == 1
	assert target.gap_size == 8
	assert target.focus_follows_mouse == false
	assert target.theme_name == 'comprehensive_test'
	
	assert target.workspace_names == ['default', 'work', 'play']
	
	assert target.keybindings['Mod+Return'] == 'exec terminal'
	assert target.keybindings['Mod+d'] == 'launcher'
	assert target.keybindings['Mod+Shift+q'] == 'close window'
	
	assert target.monitor_configs.len == 2
	assert target.monitor_configs[0].workspaces == ['web', 'dev', 'debug']
	assert target.monitor_configs[1].workspaces == ['1', '2']
}

// Test keybinding validation errors
fn test_config_keybinding_validation_errors() {
	// Test invalid keybinding format
	invalid_keybinding_content := '
[keybindings]
"InvalidKey" = "some command"
"Mod+" = "incomplete key"
"" = "empty key"
'

	test_file := '/tmp/glo55_test_invalid_keybindings.toml'
	os.write_file(test_file, invalid_keybinding_content) or {
		assert false, 'Failed to write invalid keybinding test file'
	}
	defer { os.rm(test_file) or {} }

	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		// Should fail due to invalid keybinding format
		assert err.msg().contains('Invalid keybinding')
		return
	}
	assert false, 'Invalid keybinding format should fail validation'
}

// Test workspace validation errors
fn test_config_workspace_validation_errors() {
	// Test too many workspace names
	too_many_workspaces := '
workspace_names = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"]
'

	test_file := '/tmp/glo55_test_too_many_workspaces.toml'
	os.write_file(test_file, too_many_workspaces) or {
		assert false, 'Failed to write workspace test file'
	}
	defer { os.rm(test_file) or {} }

	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert err.msg().contains('maximum 10 workspaces allowed')
		return
	}
	assert false, 'Too many workspaces should fail validation'

	// Test empty workspace names
	empty_workspace_content := '
workspace_names = ["good", "", "also_good"]
'

	test_file2 := '/tmp/glo55_test_empty_workspace.toml'
	os.write_file(test_file2, empty_workspace_content) or {
		assert false, 'Failed to write empty workspace test file'
	}
	defer { os.rm(test_file2) or {} }

	mut target2 := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target2, test_file2) or {
		assert err.msg().contains('workspace name at index 1 cannot be empty')
		return
	}
	assert false, 'Empty workspace name should fail validation'
}

// Test monitor configuration validation errors
fn test_config_monitor_validation_errors() {
	// Test duplicate workspace names in monitor
	duplicate_workspaces_content := '
[[monitors]]
workspaces = ["web", "dev", "web"]
'

	test_file := '/tmp/glo55_test_duplicate_workspaces.toml'
	os.write_file(test_file, duplicate_workspaces_content) or {
		assert false, 'Failed to write duplicate workspaces test file'
	}
	defer { os.rm(test_file) or {} }

	mut target := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target, test_file) or {
		assert err.msg().contains('duplicate workspace name "web"')
		return
	}
	assert false, 'Duplicate workspace names should fail validation'

	// Test too many workspaces in monitor
	too_many_monitor_workspaces := '
[[monitors]]
workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"]
'

	test_file2 := '/tmp/glo55_test_too_many_monitor_workspaces.toml'
	os.write_file(test_file2, too_many_monitor_workspaces) or {
		assert false, 'Failed to write too many monitor workspaces test file'
	}
	defer { os.rm(test_file2) or {} }

	mut target2 := TestConfigTarget{}
	glo55.load_config_into_from_file(mut target2, test_file2) or {
		assert err.msg().contains('maximum 10 workspaces allowed')
		return
	}
	assert false, 'Too many monitor workspaces should fail validation'
}
