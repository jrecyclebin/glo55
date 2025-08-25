module glo55

import os
import toml
import log

// MonitorConfig defines per-monitor configuration
pub struct MonitorConfig {
pub:
	workspaces []string
}

// Configuration file search paths in order of precedence
const config_search_paths = [
	'./glo55.toml', // Current directory
	'${os.home_dir()}/.config/glo55/config.toml', // User config
	'/etc/glo55/config.toml', // System config
]

// ConfigTarget interface defines objects that can receive configuration
// Uses V's structural interfaces - any object with these properties implements ConfigTarget
pub interface ConfigTarget {
mut:
	// Window manager settings
	border_width        int
	gap_size            int
	focus_follows_mouse bool
	theme_name          string
	
	// Monitor and workspace configuration
	monitor_configs     []MonitorConfig
	keybindings         map[string]string
}

// Load configuration directly into any ConfigTarget object
pub fn load_config_into(mut target ConfigTarget) ! {
	// Try to find and load config file
	config_path := find_config_file()!
	load_config_into_from_file(mut target, config_path)!
}

// Load configuration from specific file path directly into ConfigTarget object
pub fn load_config_into_from_file(mut target ConfigTarget, path string) ! {
	// Check if file exists
	if !os.exists(path) {
		return error('Configuration file not found: ${path}')
	}

	// Read file content
	content := os.read_file(path) or {
		return error('Failed to read configuration file ${path}: ${err}')
	}

	if content.len == 0 {
		log.warn('Configuration file ${path} is empty, keeping defaults')
		return
	}

	// Parse TOML content
	parsed_toml := toml.parse_text(content) or {
		return error('Failed to parse TOML in ${path}: ${err}')
	}

	// Apply TOML values directly to the target object
	apply_toml_to_target(mut target, parsed_toml, path)!
	
	log.info('Configuration loaded successfully from ${path}')
}

// Find the first available configuration file
fn find_config_file() !string {
	for path in config_search_paths {
		expanded_path := os.expand_tilde_to_home(path)
		if os.exists(expanded_path) {
			log.info('Found config file: ${expanded_path}')
			return expanded_path
		}
	}

	// If no config file found, return error
	searched_paths := config_search_paths.join(', ')
	return error('No configuration file found. Searched: ${searched_paths}')
}

// Apply parsed TOML values directly to ConfigTarget object with validation
fn apply_toml_to_target(mut target ConfigTarget, doc toml.Doc, source_path string) ! {
	// Parse window manager settings
	if border_width := get_toml_int(doc, 'border_width') {
		if border_width < 0 || border_width > 50 {
			return error('Invalid border_width in ${source_path}: must be between 0 and 50, got ${border_width}')
		}
		target.border_width = border_width
	}

	if gap_size := get_toml_int(doc, 'gap_size') {
		if gap_size < 0 || gap_size > 100 {
			return error('Invalid gap_size in ${source_path}: must be between 0 and 100, got ${gap_size}')
		}
		target.gap_size = gap_size
	}

	if focus_follows_mouse := get_toml_bool(doc, 'focus_follows_mouse') {
		target.focus_follows_mouse = focus_follows_mouse
	}

	if theme_name := get_toml_string(doc, 'theme_name') {
		if theme_name.len == 0 {
			return error('Invalid theme_name in ${source_path}: cannot be empty')
		}
		target.theme_name = theme_name
	}

	// Parse keybindings section
	if keybindings_section := get_toml_table(doc, 'keybindings') {
		target.keybindings = parse_keybindings(keybindings_section, source_path)!
	}

	// Parse monitors section
	if monitors_section := get_toml_table(doc, 'monitors') {
		target.monitor_configs = parse_monitors(monitors_section, source_path)!
	}
}

// Utility functions for safely accessing TOML values

// Get integer value from TOML document
fn get_toml_int(doc toml.Doc, key string) ?int {
	val := doc.value_opt(key) or { return none }
	return val.int()
}

// Get boolean value from TOML document
fn get_toml_bool(doc toml.Doc, key string) ?bool {
	val := doc.value_opt(key) or { return none }
	return val.bool()
}

// Get string value from TOML document
fn get_toml_string(doc toml.Doc, key string) ?string {
	val := doc.value_opt(key) or { return none }
	return val.string()
}

// Get string array value from TOML document
fn get_toml_string_array(doc toml.Doc, key string) ?[]string {
	val := doc.value_opt(key) or { return none }
	return val.array().map(it.string())
}

// Get table from TOML document
fn get_toml_table(doc toml.Doc, key string) ?toml.Any {
	val := doc.value_opt(key) or { return none }
	return val
}

// Parse keybindings from TOML section
fn parse_keybindings(keybindings_val toml.Any, source_path string) !map[string]string {
	mut keybindings := map[string]string{}
	
	// Get the keybindings as a map
	bindings_map := keybindings_val.as_map()
	for key, value in bindings_map {
		// Validate key combination format
		validate_keybinding(key, source_path)!
		
		// Get command string
		command := value.string()
		if command.trim_space().len == 0 {
			return error('Invalid keybinding in ${source_path}: command for key "${key}" cannot be empty')
		}
		
		keybindings[key] = command
	}
	
	return keybindings
}

// Validate keybinding format
fn validate_keybinding(key string, source_path string) ! {
	if key.trim_space().len == 0 {
		return error('Invalid keybinding in ${source_path}: key combination cannot be empty')
	}
	
	// Split by + to get modifiers and key
	parts := key.split('+')
	if parts.len == 0 {
		return error('Invalid keybinding "${key}" in ${source_path}: invalid format')
	}
	
	// Check for valid modifier keys
	valid_modifiers := ['Mod', 'Shift', 'Control', 'Alt']
	mut has_key := false
	
	for i, part in parts {
		trimmed_part := part.trim_space()
		if i == parts.len - 1 {
			// Last part should be the actual key
			if trimmed_part.len == 0 {
				return error('Invalid keybinding "${key}" in ${source_path}: missing actual key')
			}
			has_key = true
		} else {
			// All other parts should be valid modifiers
			if trimmed_part !in valid_modifiers {
				return error('Invalid keybinding "${key}" in ${source_path}: unknown modifier "${trimmed_part}". Valid modifiers: ${valid_modifiers.join(', ')}')
			}
		}
	}
	
	if !has_key {
		return error('Invalid keybinding "${key}" in ${source_path}: no actual key specified')
	}
}

// Parse monitors configuration from TOML section
fn parse_monitors(monitors_val toml.Any, source_path string) ![]MonitorConfig {
	mut monitors := []MonitorConfig{}
	
	// Try to get monitors as an array
	monitors_array := monitors_val.array()
	if monitors_array.len > 0 {
		// Array of monitor configurations
		for i, monitor_val in monitors_array {
			monitor_config := parse_single_monitor(monitor_val, i, source_path)!
			monitors << monitor_config
		}
	} else {
		// Single monitor configuration (not an array)
		monitor_config := parse_single_monitor(monitors_val, 0, source_path)!
		monitors << monitor_config
	}
	
	return monitors
}

// Parse a single monitor configuration
fn parse_single_monitor(monitor_val toml.Any, index int, source_path string) !MonitorConfig {
	monitor_map := monitor_val.as_map()
	
	mut workspaces := []string{}
	
	// Parse workspaces array
	if workspace_val := monitor_map['workspaces'] {
		workspace_array := workspace_val.array()
		for j, ws_val in workspace_array {
			workspace_name := ws_val.string().trim_space()
			if workspace_name.len == 0 {
				return error('Invalid monitor config in ${source_path}: workspace name at monitor ${index}, workspace ${j} cannot be empty')
			}
			workspaces << workspace_name
		}
		
		// Validate workspace count
		if workspaces.len > 10 {
			return error('Invalid monitor config in ${source_path}: monitor ${index} has ${workspaces.len} workspaces, maximum 10 allowed')
		}
		
		// Validate workspace name uniqueness within this monitor
		mut seen := map[string]bool{}
		for workspace_name in workspaces {
			if seen[workspace_name] {
				return error('Invalid monitor config in ${source_path}: monitor ${index} has duplicate workspace name "${workspace_name}"')
			}
			seen[workspace_name] = true
		}
	}
	
	return MonitorConfig{
		workspaces: workspaces
	}
}

// Validate configuration values for any ConfigTarget object
pub fn validate_config_target(target ConfigTarget) ! {
	if target.border_width < 0 || target.border_width > 50 {
		return error('Invalid border_width: must be between 0 and 50, got ${target.border_width}')
	}

	if target.gap_size < 0 || target.gap_size > 100 {
		return error('Invalid gap_size: must be between 0 and 100, got ${target.gap_size}')
	}

	if target.theme_name.len == 0 {
		return error('Invalid theme_name: cannot be empty')
	}

	// Validate keybindings
	for key, command in target.keybindings {
		validate_keybinding(key, 'configuration')!
		if command.trim_space().len == 0 {
			return error('Invalid keybinding: command for key "${key}" cannot be empty')
		}
	}

	// Validate monitor configurations
	for i, monitor in target.monitor_configs {
		if monitor.workspaces.len > 10 {
			return error('Invalid monitor ${i}: maximum 10 workspaces allowed, got ${monitor.workspaces.len}')
		}
		
		// Validate workspace name uniqueness within this monitor
		mut seen := map[string]bool{}
		for j, workspace_name in monitor.workspaces {
			if workspace_name.trim_space().len == 0 {
				return error('Invalid monitor ${i}: workspace name at index ${j} cannot be empty')
			}
			if seen[workspace_name] {
				return error('Invalid monitor ${i}: duplicate workspace name "${workspace_name}"')
			}
			seen[workspace_name] = true
		}
	}
}
