import json
from pathlib import Path

import pytest

from nuro.registry import apply_unsafe_dev_mode_from_marker, load_registry
from nuro.paths import buckets_path


@pytest.fixture()
def isolated_home(tmp_path, monkeypatch):
    """一時ホームディレクトリを設定する"""
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("USERPROFILE", str(tmp_path))
    return tmp_path


def test_apply_unsafe_mode_without_marker(isolated_home):
    """マーカーが無い場合は何も更新されない"""
    reg_before = load_registry()
    assert all("unsafe-dev-mode" not in b for b in reg_before["buckets"])

    updated = apply_unsafe_dev_mode_from_marker()

    assert updated is False
    reg_after = load_registry()
    assert all("unsafe-dev-mode" not in b for b in reg_after["buckets"])


def test_apply_unsafe_mode_with_marker(isolated_home):
    """マーカーが存在する場合は全バケットがunsafeになる"""
    marker = isolated_home / ".nuro" / "nusafedevmode"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.touch()

    updated = apply_unsafe_dev_mode_from_marker()

    assert updated is True
    reg_after = load_registry()
    assert reg_after["buckets"], "バケット配列が空ではいけない"
    for bucket in reg_after["buckets"]:
        assert bucket.get("unsafe-dev-mode") is True

    data = json.loads(buckets_path().read_text(encoding="utf-8"))
    for bucket in data["buckets"]:
        assert bucket.get("unsafe-dev-mode") is True
