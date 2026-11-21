"""Regression tests for macOS dotfiles setup, theme switcher, and Kitty tab bar."""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
THEMES_DIR = REPO / "themes"


def _load_tab_bar_module():
    """Import kitty/tab_bar.py with lightweight stubs for kitty's runtime API."""
    fake_kitty = types.ModuleType("kitty")
    fake_fast = types.ModuleType("kitty.fast_data_types")
    fake_fast.Screen = object
    fake_fast.get_boss = lambda: None
    fake_tab_bar = types.ModuleType("kitty.tab_bar")
    fake_tab_bar.DrawData = object
    fake_tab_bar.ExtraData = object
    fake_tab_bar.TabBarData = object
    fake_tab_bar.as_rgb = lambda x: x

    saved = {k: sys.modules.get(k) for k in ("kitty", "kitty.fast_data_types", "kitty.tab_bar")}
    sys.modules["kitty"] = fake_kitty
    sys.modules["kitty.fast_data_types"] = fake_fast
    sys.modules["kitty.tab_bar"] = fake_tab_bar
    try:
        spec = importlib.util.spec_from_file_location("kitty_tab_bar", REPO / "kitty" / "tab_bar.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


class ThemeScriptTests(unittest.TestCase):
    def test_all_themes_generate_expected_files(self):
        themes = sorted(p.name for p in THEMES_DIR.iterdir() if p.is_dir())
        self.assertGreaterEqual(len(themes), 5)

        with tempfile.TemporaryDirectory() as tmp:
            config_dir = pathlib.Path(tmp) / "config"
            env = {**os.environ, "DOTFILES_CONFIG_DIR": str(config_dir)}
            for name in themes:
                res = subprocess.run(
                    [str(REPO / "bin" / "theme"), "--no-reload", name],
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(res.returncode, 0, f"theme {name} failed: {res.stderr}")

                state = config_dir / "dotfiles-theme"
                self.assertEqual((state / "name").read_text().strip(), name)
                self.assertTrue((state / "kitty.conf").is_symlink())
                self.assertTrue((state / "nvim.lua").is_symlink())

                for fname in (
                    "kitty-tabs.conf",
                    "kitty-palette.json",
                    "tmux.conf",
                    "mpv.conf",
                    "btop.theme",
                    "lazygit.yml",
                    "delta.gitconfig",
                    "fzf.opts",
                ):
                    self.assertTrue((state / fname).is_file(), f"missing {fname} for {name}")

                palette = json.loads((state / "kitty-palette.json").read_text())
                for role in ("bg", "bg_dim", "surface", "overlay", "border", "fg", "muted", "accent", "accent2", "warn", "error", "success"):
                    self.assertRegex(palette[role], r"^#[0-9a-fA-F]{6}$")

                tmux_conf = (state / "tmux.conf").read_text()
                self.assertIn("window-status-format", tmux_conf)
                self.assertIn("window-status-current-format", tmux_conf)

                self.assertTrue((config_dir / "starship.toml").is_file())
                self.assertTrue((config_dir / "ghostty" / "themes" / "dotfiles").is_file())
                self.assertTrue((config_dir / "bat" / "config").is_file())

    def test_rejects_invalid_theme_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = {**os.environ, "DOTFILES_CONFIG_DIR": tmp}
            res = subprocess.run(
                [str(REPO / "bin" / "theme"), "--no-reload", "../etc/passwd"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("Unknown theme", res.stderr)


class SetupScriptTests(unittest.TestCase):
    def test_dry_run_links_expected_configs(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = subprocess.run(
                ["bash", str(REPO / "setup.sh"), "--dry-run", "--target-dir", tmp],
                capture_output=True,
                text=True,
            )
            self.assertEqual(res.returncode, 0, res.stderr)
            out = res.stdout
            for expected in (
                ".tmux.conf",
                ".local/bin/theme",
                ".config/dotfiles/theme.zsh",
                ".config/kitty/kitty.conf",
                ".config/kitty/tab_bar.py",
                ".config/nvim/init.lua",
                ".config/lazygit/config.yml",
                ".config/yazi/yazi.toml",
            ):
                self.assertIn(expected, out)


class KittyTabBarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = _load_tab_bar_module()

    def test_format_title_recognizes_apps_and_paths(self):
        icon, title = self.mod._format_title("nvim /Users/kamal/dotfiles/init.lua")
        self.assertEqual(icon, self.mod.APP_ICONS["nvim"])
        self.assertEqual(title, "init.lua")

        icon, title = self.mod._format_title("~/projects/demo/")
        self.assertEqual(icon, self.mod.FOLDER_ICON)
        self.assertEqual(title, "demo")

        icon, title = self.mod._format_title("⠋ lazygit")
        self.assertEqual(icon, self.mod.APP_ICONS["lazygit"])
        self.assertEqual(title, "lazygit")

    def test_truncate_respects_limit(self):
        self.assertEqual(self.mod._truncate("hello", 10), "hello")
        self.assertEqual(self.mod._truncate("abcdefghij", 5), "abcd…")
        self.assertEqual(self.mod._truncate("abc", 1), "…")

    def test_load_palette_reads_xdg_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            theme_dir = pathlib.Path(tmp) / "dotfiles-theme"
            theme_dir.mkdir()
            (theme_dir / "kitty-palette.json").write_text(json.dumps({"accent": "#112233"}))

            old_xdg = os.environ.get("XDG_CONFIG_HOME")
            os.environ["XDG_CONFIG_HOME"] = tmp
            self.mod._palette_cache.update({"mtime": -1, "colors": None})
            try:
                colors = self.mod._load_palette()
                self.assertEqual(colors["accent"], 0x112233)
            finally:
                if old_xdg is None:
                    os.environ.pop("XDG_CONFIG_HOME", None)
                else:
                    os.environ["XDG_CONFIG_HOME"] = old_xdg
                self.mod._palette_cache.update({"mtime": -1, "colors": None})


if __name__ == "__main__":
    unittest.main()
