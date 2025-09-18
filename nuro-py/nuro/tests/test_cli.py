import pytest

from nuro import cli


@pytest.fixture()
def isolated_home(tmp_path, monkeypatch):
    """一時ホームディレクトリを設定する"""
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("USERPROFILE", str(tmp_path))
    return tmp_path


def test_main_invokes_marker_when_no_args(isolated_home, monkeypatch):
    """引数なし実行時にunsafeマーカー適用が呼ばれる"""
    called = {
        "apply": 0,
        "refresh": None,
    }

    def fake_apply():
        called["apply"] += 1
        return False

    def fake_print(refresh):
        called["refresh"] = refresh

    monkeypatch.setattr(cli, "apply_unsafe_dev_mode_from_marker", fake_apply)
    monkeypatch.setattr(cli, "print_root_usage", fake_print)

    exit_code = cli.main([])

    assert exit_code == 0
    assert called["apply"] == 1
    assert called["refresh"] is False


def test_main_invokes_marker_on_refresh(isolated_home, monkeypatch):
    """--refresh 指定時もunsafeマーカー適用が呼ばれる"""
    called = {
        "apply": 0,
        "refresh": None,
    }

    def fake_apply():
        called["apply"] += 1
        return False

    def fake_print(refresh):
        called["refresh"] = refresh

    monkeypatch.setattr(cli, "apply_unsafe_dev_mode_from_marker", fake_apply)
    monkeypatch.setattr(cli, "print_root_usage", fake_print)

    exit_code = cli.main(["--refresh"])

    assert exit_code == 0
    assert called["apply"] == 1
    assert called["refresh"] is True
