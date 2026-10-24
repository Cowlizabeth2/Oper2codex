import pytest
from tools.build_windows import resolve_commit


def test_full_build_sha_is_kept_without_truncation(monkeypatch,tmp_path):
    sha='1234567890abcdef1234567890abcdef12345678'
    monkeypatch.setenv('GITHUB_SHA',sha)
    assert resolve_commit(tmp_path)==sha


@pytest.mark.parametrize('value',['shortsha','local','a'*8,''])
def test_invalid_build_identity_cannot_be_published(monkeypatch,tmp_path,value):
    monkeypatch.setenv('GITHUB_SHA',value or 'not-a-sha')
    with pytest.raises(ValueError): resolve_commit(tmp_path)
