"""Collect a small NA1 Gold I ranked-solo match cohort into the raw GCS bucket.

The default run reads the first 10 Gold I players and requests up to 20 recent
ranked-solo matches for each. Match IDs are deduplicated before download. The
Riot key is read only from Google Secret Manager.
"""

from __future__ import annotations

import argparse
import json
import re
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import quote

import requests
from google.api_core.exceptions import PreconditionFailed
from google.cloud import secretmanager, storage

AMERICAS_BASE_URL = "https://americas.api.riotgames.com"
NA1_BASE_URL = "https://na1.api.riotgames.com"
RANKED_SOLO_QUEUE_ID = 420
GCP_PROJECT_ID_PATTERN = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")


class RiotApiError(RuntimeError):
    """An HTTP error returned by the Riot API."""


@dataclass(frozen=True)
class IngestionConfig:
    project_id: str
    raw_bucket: str
    player_count: int
    matches_per_player: int
    request_delay_seconds: float
    secret_id: str


class RiotClient:
    """Rate-limited adapter for the NA1 League and Americas Match-V5 endpoints."""

    def __init__(self, api_key: str, request_delay_seconds: float) -> None:
        self._session = requests.Session()
        self._session.headers.update({"X-Riot-Token": api_key})
        self._request_delay_seconds = request_delay_seconds
        self._last_request_started = 0.0

    def get_gold_one_puuids(self, count: int) -> list[str]:
        response = self._get(
            NA1_BASE_URL,
            "/lol/league/v4/entries/RANKED_SOLO_5x5/GOLD/I",
            params={"page": 1},
        )
        entries = response.json()[:count]
        missing_puuid = [entry for entry in entries if not entry.get("puuid")]
        if missing_puuid:
            raise RiotApiError("Riot League entries did not contain the required 'puuid' field.")
        return [entry["puuid"] for entry in entries]

    def get_ranked_solo_match_ids(self, puuid: str, count: int) -> list[str]:
        response = self._get(
            AMERICAS_BASE_URL,
            f"/lol/match/v5/matches/by-puuid/{quote(puuid, safe='')}/ids",
            params={"start": 0, "count": count, "queue": RANKED_SOLO_QUEUE_ID},
        )
        return response.json()

    def get_match_raw_json(self, match_id: str) -> bytes:
        return self._get(
            AMERICAS_BASE_URL,
            f"/lol/match/v5/matches/{quote(match_id, safe='')}",
        ).content

    def _get(self, base_url: str, path: str, params: dict[str, int] | None = None) -> requests.Response:
        for attempt in range(3):
            wait_seconds = self._request_delay_seconds - (time.monotonic() - self._last_request_started)
            if wait_seconds > 0:
                time.sleep(wait_seconds)

            self._last_request_started = time.monotonic()
            response = self._session.get(f"{base_url}{path}", params=params, timeout=30)
            if response.status_code != 429:
                break

            retry_after = float(response.headers.get("Retry-After", "10"))
            print(f"Riot rate limit reached; waiting {retry_after:.0f} seconds before retrying.")
            time.sleep(retry_after)
        else:
            raise RiotApiError("Riot rate limit persisted after three retries. Run again later.")

        if response.status_code == 401:
            raise RiotApiError("Riot rejected the API key. Development keys expire every 24 hours.")
        if response.status_code == 404:
            raise RiotApiError("Riot could not find a requested player or match.")
        try:
            response.raise_for_status()
        except requests.HTTPError as error:
            raise RiotApiError(f"Riot API returned HTTP {response.status_code}.") from error
        return response


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-id", required=True, help="GCP project ID.")
    parser.add_argument("--raw-bucket", required=True, help="GCS raw-bucket name from Terraform output.")
    parser.add_argument("--player-count", type=int, default=10, help="Gold I players to sample, from 1 to 10.")
    parser.add_argument("--matches-per-player", type=int, default=20, help="Recent ranked-solo matches per player, from 1 to 20.")
    parser.add_argument("--request-delay-seconds", type=float, default=1.3, help="Pause between Riot requests. Default: 1.3.")
    parser.add_argument("--secret-id", default="riot-api-key", help="Secret Manager secret ID.")
    return parser.parse_args()


def validate_project_id(project_id: str) -> None:
    """Fail early when a shell variable or tutorial placeholder is passed as a project ID."""
    if not GCP_PROJECT_ID_PATTERN.fullmatch(project_id):
        raise ValueError(
            "--project-id must be a GCP project ID, for example 'self-learn-spark'. "
            "Do not pass an empty variable or the text YOUR_GCP_PROJECT_ID."
        )


def read_riot_api_key(project_id: str, secret_id: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    secret_version = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": secret_version})
    return response.payload.data.decode("utf-8")


def raw_match_object_name(match_id: str) -> str:
    """Return the one permanent raw-data location for a Riot match."""
    return f"matches/match_id={match_id}.json"


def raw_run_manifest_object_name(run_id: str, ingest_date: str) -> str:
    """Return a unique audit-file location for one ingestion run."""
    return f"ingestion-runs/ingest_date={ingest_date}/run_id={run_id}.json"


def raw_match_exists(storage_client: storage.Client, bucket_name: str, match_id: str) -> bool:
    """Check whether a prior run already saved this immutable match payload."""
    blob = storage_client.bucket(bucket_name).blob(raw_match_object_name(match_id))
    return blob.exists(client=storage_client)


def upload_raw_match(
    storage_client: storage.Client,
    bucket_name: str,
    match_id: str,
    raw_json: bytes,
) -> bool:
    """Create a raw match once.

    ``if_generation_match=0`` is GCS's create-only guard.  A concurrent run
    that wins the race is not an error: this run simply reports the match as
    already present.
    """
    blob = storage_client.bucket(bucket_name).blob(raw_match_object_name(match_id))
    try:
        blob.upload_from_string(
            raw_json,
            content_type="application/json",
            if_generation_match=0,
        )
    except PreconditionFailed:
        return False
    return True


def upload_run_manifest(
    storage_client: storage.Client,
    bucket_name: str,
    run_id: str,
    started_at: datetime,
    match_ids: list[str],
    uploaded_new: int,
    skipped_existing: int,
) -> str:
    """Write an audit record, separate from the canonical raw match files."""
    object_name = raw_run_manifest_object_name(run_id, started_at.date().isoformat())
    manifest = {
        "run_id": run_id,
        "started_at": started_at.isoformat(),
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "unique_match_ids": match_ids,
        "unique_match_count": len(match_ids),
        "uploaded_new": uploaded_new,
        "skipped_existing": skipped_existing,
    }
    storage_client.bucket(bucket_name).blob(object_name).upload_from_string(
        json.dumps(manifest, sort_keys=True),
        content_type="application/json",
        if_generation_match=0,
    )
    return object_name


def ingest(config: IngestionConfig) -> tuple[int, int, int, int, str]:
    api_key = read_riot_api_key(config.project_id, config.secret_id)
    riot_client = RiotClient(api_key, config.request_delay_seconds)
    puuids = riot_client.get_gold_one_puuids(config.player_count)

    match_ids: list[str] = []
    for player_number, puuid in enumerate(puuids, start=1):
        print(f"Finding matches for Gold I player {player_number}/{len(puuids)}...")
        match_ids.extend(riot_client.get_ranked_solo_match_ids(puuid, config.matches_per_player))

    unique_match_ids = list(dict.fromkeys(match_ids))
    print(f"Found {len(match_ids)} player-match references and {len(unique_match_ids)} unique matches.")

    started_at = datetime.now(timezone.utc)
    run_id = f"{started_at.strftime('%Y%m%dT%H%M%SZ')}-{uuid.uuid4().hex[:8]}"
    storage_client = storage.Client(project=config.project_id)
    uploaded_new = 0
    skipped_existing = 0
    for match_number, match_id in enumerate(unique_match_ids, start=1):
        if raw_match_exists(storage_client, config.raw_bucket, match_id):
            skipped_existing += 1
            print(f"Skipping existing match {match_number}/{len(unique_match_ids)}: {match_id}")
            continue

        print(f"Downloading and storing match {match_number}/{len(unique_match_ids)}: {match_id}")
        raw_json = riot_client.get_match_raw_json(match_id)
        if upload_raw_match(storage_client, config.raw_bucket, match_id, raw_json):
            uploaded_new += 1
        else:
            skipped_existing += 1
            print(f"Another run already stored {match_id}; safely skipped.")

    manifest_object = upload_run_manifest(
        storage_client,
        config.raw_bucket,
        run_id,
        started_at,
        unique_match_ids,
        uploaded_new,
        skipped_existing,
    )
    return len(puuids), len(unique_match_ids), uploaded_new, skipped_existing, manifest_object


def main() -> None:
    args = parse_args()
    validate_project_id(args.project_id)
    if not 1 <= args.player_count <= 10:
        raise ValueError("--player-count must be between 1 and 10.")
    if not 1 <= args.matches_per_player <= 20:
        raise ValueError("--matches-per-player must be between 1 and 20.")
    if args.request_delay_seconds < 1.2:
        raise ValueError("--request-delay-seconds must be at least 1.2 for this development-key exercise.")

    players, unique_matches, uploaded_new, skipped_existing, manifest_object = ingest(
        IngestionConfig(
            project_id=args.project_id,
            raw_bucket=args.raw_bucket,
            player_count=args.player_count,
            matches_per_player=args.matches_per_player,
            request_delay_seconds=args.request_delay_seconds,
            secret_id=args.secret_id,
        )
    )
    print(
        f"Finished: {players} players, {unique_matches} unique matches, "
        f"{uploaded_new} new files, {skipped_existing} existing files skipped."
    )
    print(f"Run manifest: gs://{args.raw_bucket}/{manifest_object}")


if __name__ == "__main__":
    main()
