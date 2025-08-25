module glo55

import os
import toml
import log

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
	
	// Future extensibility for keybindings and workspace configuration
	keybindings         map[string]string
	workspace_names     []string
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

	// TODO: Add parsing for keybindings and workspace_names when they're needed
	// For now, these remain as empty/default values set in the struct definitions
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
}
