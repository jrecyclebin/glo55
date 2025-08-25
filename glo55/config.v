module glo55

import os
import toml
import log

// Configuration file search paths in order of precedence
const config_search_paths = [
	'./glo55.toml', // Current directory
	'${os.home_dir()}/config/glo55/config.toml', // User config
	'/etc/glo55/config.toml', // System config
]

// Configuration structure
pub struct Config {
pub mut:
	// Window manager configuration
	border_width        int  = 2
	gap_size            int  = 10
	focus_follows_mouse bool = true

	// Theme configuration (will be expanded later)
	theme_name string = 'default'
}

// Load configuration from TOML file with fallback to defaults
pub fn Config.load() !Config {
	// Try to find and load config file
	config_path := find_config_file()!
	return load_config_from_file(config_path)!
}

// Load configuration from specific file path
pub fn Config.from_file(path string) !Config {
	return load_config_from_file(path)!
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

// Load and parse TOML configuration from file
fn load_config_from_file(path string) !Config {
	// Check if file exists
	if !os.exists(path) {
		return error('Configuration file not found: ${path}')
	}

	// Read file content
	content := os.read_file(path) or {
		return error('Failed to read configuration file ${path}: ${err}')
	}

	if content.len == 0 {
		log.warn('Configuration file ${path} is empty, using defaults')
		return Config{}
	}

	// Parse TOML content
	parsed_toml := toml.parse_text(content) or {
		return error('Failed to parse TOML in ${path}: ${err}')
	}

	// Convert TOML to Config struct
	return toml_to_config(parsed_toml, path)!
}

// Convert parsed TOML to Config struct with validation
fn toml_to_config(doc toml.Doc, source_path string) !Config {
	mut config := Config{}

	// Parse window manager settings
	if border_width := get_toml_int(doc, 'border_width') {
		if border_width < 0 || border_width > 50 {
			return error('Invalid border_width in ${source_path}: must be between 0 and 50, got ${border_width}')
		}
		config.border_width = border_width
	}

	if gap_size := get_toml_int(doc, 'gap_size') {
		if gap_size < 0 || gap_size > 100 {
			return error('Invalid gap_size in ${source_path}: must be between 0 and 100, got ${gap_size}')
		}
		config.gap_size = gap_size
	}

	if focus_follows_mouse := get_toml_bool(doc, 'focus_follows_mouse') {
		config.focus_follows_mouse = focus_follows_mouse
	}

	if theme_name := get_toml_string(doc, 'theme_name') {
		if theme_name.len == 0 {
			return error('Invalid theme_name in ${source_path}: cannot be empty')
		}
		config.theme_name = theme_name
	}

	log.info('Configuration loaded successfully from ${source_path}')
	return config
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

// Get default configuration
pub fn Config.default() Config {
	return Config{}
}

// Validate configuration values
pub fn (config Config) validate() ! {
	if config.border_width < 0 || config.border_width > 50 {
		return error('Invalid border_width: must be between 0 and 50, got ${config.border_width}')
	}

	if config.gap_size < 0 || config.gap_size > 100 {
		return error('Invalid gap_size: must be between 0 and 100, got ${config.gap_size}')
	}

	if config.theme_name.len == 0 {
		return error('Invalid theme_name: cannot be empty')
	}
}
