module glo55

// paths.v - where an installed Glo55 keeps its default config and bundled
// themes (`make install`), and how a theme named in a config is found.
import os

// baked_prefix is the PREFIX the binary was built for: `make PREFIX=/usr` passes
// `-d glo55_prefix=/usr` (the default for a plain build is /usr/local).
pub const baked_prefix = $d('glo55_prefix', '/usr/local')

// data_dirs lists the places that may hold Glo55's installed files
// (config.toml and themes/), best first, existing directories only:
//  1. $GLO55_DATADIR (override, also handy for tests),
//  2. <dir of the binary>/../share/glo55 (a relocated or staged install works),
//  3. <PREFIX baked in at build time>/share/glo55.
pub fn data_dirs(exe string) []string {
	mut cands := []string{}
	env := os.getenv('GLO55_DATADIR')
	if env != '' {
		cands << env
	}
	if exe != '' {
		cands << os.join_path(os.dir(os.dir(exe)), 'share', 'glo55')
	}
	cands << os.join_path(baked_prefix, 'share', 'glo55')
	mut out := []string{}
	for c in cands {
		if os.is_dir(c) && c !in out {
			out << c
		}
	}
	return out
}

// installed_config is the default config.toml of an installed Glo55 ('' if none).
pub fn installed_config(exe string) string {
	for d in data_dirs(exe) {
		p := os.join_path(d, 'config.toml')
		if os.is_file(p) {
			return p
		}
	}
	return ''
}

// resolve_theme finds the theme file a config names. `rel` is the path as
// written in the config. In order it tries: next to the config file, the
// user's ~/.config/glo55/themes/, then the installed themes of each data
// directory (share/glo55/themes/). A leading "themes/" in `rel` (the layout of
// the source tree) is optional for the last two. If nothing exists the first
// candidate is returned, so the error message names a sensible path.
pub fn resolve_theme(config_dir string, rel string, user_config_dir string, datadirs []string) string {
	first := resolve_path(config_dir, rel)
	if os.is_abs_path(rel) || os.exists(first) {
		return first
	}
	name := rel.trim_string_left('themes/')
	mut cands := []string{}
	if user_config_dir != '' {
		cands << os.join_path(user_config_dir, 'glo55', 'themes', name)
	}
	for d in datadirs {
		cands << os.join_path(d, 'themes', name)
	}
	for c in cands {
		if os.exists(c) {
			return c
		}
	}
	return first
}
