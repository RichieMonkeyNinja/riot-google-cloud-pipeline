"""Small tests for local validation in the Riot ingestion entry point."""

import pytest
from google.api_core.exceptions import PreconditionFailed

from src.extract_gold_matches import (
    RiotApiError,
    RiotClient,
    raw_match_object_name,
    upload_raw_match,
    validate_project_id,
)


def test_valid_project_id_is_accepted() -> None:
    validate_project_id("self-learn-spark")


@pytest.mark.parametrize("project_id", ["", "YOUR_GCP_PROJECT_ID", "Self Learn Spark"])
def test_placeholder_or_malformed_project_id_is_rejected(project_id: str) -> None:
    with pytest.raises(ValueError, match="--project-id must be a GCP project ID"):
        validate_project_id(project_id)


class _StubResponse:
    def __init__(self, payload: list[dict[str, str]]) -> None:
        self._payload = payload

    def json(self) -> list[dict[str, str]]:
        return self._payload


def test_gold_league_entries_use_puuid_directly(monkeypatch: pytest.MonkeyPatch) -> None:
    client = RiotClient(api_key="not-used", request_delay_seconds=1.2)
    monkeypatch.setattr(
        client,
        "_get",
        lambda *_args, **_kwargs: _StubResponse([{"puuid": "player-a"}, {"puuid": "player-b"}]),
    )

    assert client.get_gold_one_puuids(1) == ["player-a"]


def test_gold_league_entries_without_puuid_fail_clearly(monkeypatch: pytest.MonkeyPatch) -> None:
    client = RiotClient(api_key="not-used", request_delay_seconds=1.2)
    monkeypatch.setattr(client, "_get", lambda *_args, **_kwargs: _StubResponse([{}]))

    with pytest.raises(RiotApiError, match="required 'puuid' field"):
        client.get_gold_one_puuids(1)


def test_raw_match_path_is_canonical_per_match_id() -> None:
    assert raw_match_object_name("NA1_123") == "matches/match_id=NA1_123.json"


class _FakeBlob:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error
        self.upload_kwargs: dict[str, object] | None = None

    def upload_from_string(self, _payload: bytes, **kwargs: object) -> None:
        self.upload_kwargs = kwargs
        if self.error:
            raise self.error


class _FakeBucket:
    def __init__(self, blob: _FakeBlob) -> None:
        self._blob = blob

    def blob(self, _name: str) -> _FakeBlob:
        return self._blob


class _FakeStorageClient:
    def __init__(self, blob: _FakeBlob) -> None:
        self._bucket = _FakeBucket(blob)

    def bucket(self, _name: str) -> _FakeBucket:
        return self._bucket


def test_raw_upload_is_create_only() -> None:
    blob = _FakeBlob()

    assert upload_raw_match(_FakeStorageClient(blob), "raw-bucket", "NA1_123", b"{}") is True
    assert blob.upload_kwargs == {"content_type": "application/json", "if_generation_match": 0}


def test_concurrent_raw_upload_is_safely_skipped() -> None:
    blob = _FakeBlob(PreconditionFailed("already exists"))

    assert upload_raw_match(_FakeStorageClient(blob), "raw-bucket", "NA1_123", b"{}") is False
