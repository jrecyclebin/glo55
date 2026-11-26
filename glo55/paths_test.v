module glo55

import os

fn mk_tree() !string {
	root := os.join_path(os.temp_dir(), 'glo55-paths-${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'cfg', 'themes', 'mine'))!
	os.mkdir_all(os.join_path(root, 'data1', 'themes', 'steel'))!
	os.mkdir_all(os.join_path(root, 'data2', 'themes', 'steel'))!
	os.mkdir_all(os.join_path(root, 'user', 'glo55', 'themes', 'steel'))!
	os.mkdir_all(os.join_path(root, 'etc'))!
	for p in ['cfg/themes/mine/theme.toml', 'data1/themes/steel/theme.toml',
		'data2/themes/steel/theme.toml', 'user/glo55/themes/steel/theme.toml',
		'data2/themes/only2.toml'] {
		os.write_file(os.join_path(root, p), '')!
	}
	return root
}

fn test_resolve_theme_prefers_the_config_dir_then_user_then_installed() {
	root := mk_tree()!
	defer {
		os.rmdir_all(root) or {}
	}
	cfg := os.join_path(root, 'cfg')
	user := os.join_path(root, 'user')
	d1 := os.join_path(root, 'data1')
	d2 := os.join_path(root, 'data2')
	// next to the config file
	assert resolve_theme(cfg, 'themes/mine/theme.toml', user, [d1, d2]) == os.join_path(cfg,
		'themes/mine/theme.toml')
	// ~/.config/glo55/themes before the installed ones; "themes/" prefix optional
	assert resolve_theme(cfg, 'steel/theme.toml', user, [d1, d2]) == os.join_path(user,
		'glo55/themes/steel/theme.toml')
	assert resolve_theme(cfg, 'themes/steel/theme.toml', user, [d1, d2]) == os.join_path(user,
		'glo55/themes/steel/theme.toml')
	// no user copy: the first data dir that has it
	assert resolve_theme(cfg, 'steel/theme.toml', '', [d1, d2]) == os.join_path(d1,
		'themes/steel/theme.toml')
	assert resolve_theme(cfg, 'only2.toml', '', [d1, d2]) == os.join_path(d2, 'themes/only2.toml')
	// absolute paths are left alone; unknown names give the config-relative path (for the error message)
	assert resolve_theme(cfg, '/nonexistent/t.toml', user, [d1]) == '/nonexistent/t.toml'
	assert resolve_theme(cfg, 'nope/theme.toml', user, [d1]) == os.join_path(cfg, 'nope/theme.toml')
}

fn test_data_dirs_env_override_and_binary_relative() {
	root := mk_tree()!
	defer {
		os.rmdir_all(root) or {}
	}
	os.mkdir_all(os.join_path(root, 'inst', 'bin'))!
	os.mkdir_all(os.join_path(root, 'inst', 'share', 'glo55'))!
	exe := os.join_path(root, 'inst', 'bin', 'glo55')
	rel := os.join_path(root, 'inst', 'share', 'glo55')
	os.unsetenv('GLO55_DATADIR')
	assert data_dirs(exe)[0] == rel // <bin>/../share/glo55
	os.setenv('GLO55_DATADIR', os.join_path(root, 'data1'), true)
	assert data_dirs(exe)[0] == os.join_path(root, 'data1') // the override comes first
	assert rel in data_dirs(exe)
	os.setenv('GLO55_DATADIR', os.join_path(root, 'does-not-exist'), true)
	assert data_dirs(exe)[0] == rel // only existing directories are listed
	os.unsetenv('GLO55_DATADIR')
	// installed_config looks for config.toml in the data dirs. The override and
	// the binary-relative dir both come before the baked prefix, so the test
	// stays hermetic even on a machine with glo55 installed under it.
	os.write_file(os.join_path(root, 'data1', 'config.toml'), '')!
	os.setenv('GLO55_DATADIR', os.join_path(root, 'data1'), true)
	assert installed_config(exe) == os.join_path(root, 'data1', 'config.toml') // the override wins
	os.unsetenv('GLO55_DATADIR')
	os.write_file(os.join_path(rel, 'config.toml'), '')!
	assert installed_config(exe) == os.join_path(rel, 'config.toml') // <bin>/../share/glo55 before the baked prefix
}
