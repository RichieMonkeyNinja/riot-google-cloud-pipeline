"""Fetch a small NA1 League of Legends match sample and save raw JSON to GCS.

The Riot API key is read from Google Secret Manager. It is never accepted as a
command-line argument, written to disk, or printed.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import quote

import google.auth
import requests
from google.cloud import secretmanager, storage

AMERICAS_BASE_URL = "https://americas.api.riotgames.com"


class RiotApiError(RuntimeError):
    """An HTTP error returned by the Riot API."""


@dataclass(frozen=True)
class IngestionConfig:
    project_id: str
    raw_bucket: str
    game_name: str
    tag_line: str
    match_count: int
    secret_id: str


class RiotClient:
    """Small adapter for the Riot account and Match-V5 endpoints."""

    def __init__(self, api_key: str) -> None:
        self._session = requests.Session()
        self._session.headers.update({"X-Riot-Token": api_key})

    def get_puuid(self, game_name: str, tag_line: str) -> str:
        response = self._get(
            "/riot/account/v1/accounts/by-riot-id/"
            f"{quote(game_name, safe='')}/{quote(tag_line, safe='')}"
        )
        return response.json()["puuid"]

    def get_match_ids(self, puuid: str, count: int) -> list[str]:
        response = self._get(
            f"/lol/match/v5/matches/by-puuid/{quote(puuid, safe='')}/ids",
            params={"start": 0, "count": count},
        )
        return response.json()

    def get_match_raw_json(self, match_id: str) -> bytes:
        return self._get(f"/lol/match/v5/matches/{quote(match_id, safe='')}").content

    def _get(self, path: str, params: dict[str, int] | None = None) -> requests.Response:
        response = self._session.get(f"{AMERICAS_BASE_URL}{path}", params=params, timeout=30)
        if response.status_code == 401:
            raise RiotApiError("Riot rejected the API key. Development keys expire every 24 hours.")
        if response.status_code == 404:
            raise RiotApiError("Riot could not find that Riot ID or match.")
        if response.status_code == 429:
            raise RiotApiError("Riot rate limit reached. Wait before running the extractor again.")
        try:
            response.raise_for_status()
        except requests.HTTPError as error:
            raise RiotApiError(f"Riot API returned HTTP {response.status_code}.") from error
        return response


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-bucket", required=True, help="GCS raw-bucket name from Terraform output.")
    parser.add_argument("--game-name", required=True, help="Riot ID game name, before the # symbol.")
    parser.add_argument("--tag-line", required=True, help="Riot ID tag line, after the # symbol.")
    parser.add_argument("--project-id", help="GCP project ID. Defaults to the ADC project, if available.")
    parser.add_argument("--count", type=int, default=3, help="Matches to fetch, from 1 to 5. Default: 3.")
    parser.add_argument("--secret-id", default="riot-api-key", help="Secret Manager secret ID.")
    return parser.parse_args()


def get_project_id(argument_project_id: str | None) -> str:
    if argument_project_id:
        return argument_project_id
    _, adc_project_id = google.auth.default()
    if not adc_project_id:
        raise ValueError("No project ID found. Pass --project-id explicitly.")
    return adc_project_id


def read_riot_api_key(project_id: str, secret_id: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    secret_version = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": secret_version})
    return response.payload.data.decode("utf-8")


def upload_raw_match(storage_client: storage.Client, bucket_name: str, match_id: str, raw_json: bytes) -> str:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    ingest_date = datetime.now(timezone.utc).date().isoformat()
    object_name = f"match-details/ingest_date={ingest_date}/run_id={run_id}/match_id={match_id}.json"
    storage_client.bucket(bucket_name).blob(object_name).upload_from_string(
        raw_json,
        content_type="application/json",
    )
    return object_name


def ingest(config: IngestionConfig) -> list[str]:
    api_key = read_riot_api_key(config.project_id, config.secret_id)
    riot_client = RiotClient(api_key)
    puuid = riot_client.get_puuid(config.game_name, config.tag_line)
    match_ids = riot_client.get_match_ids(puuid, config.match_count)
    storage_client = storage.Client(project=config.project_id)

    uploaded_objects = []
    for match_id in match_ids:
        raw_json = riot_client.get_match_raw_json(match_id)
        uploaded_objects.append(upload_raw_match(storage_client, config.raw_bucket, match_id, raw_json))
    return uploaded_objects


def main() -> None:
    args = parse_args()
    if not 1 <= args.count <= 5:
        raise ValueError("--count must be between 1 and 5 for this learning exercise.")

    config = IngestionConfig(
        project_id=get_project_id(args.project_id),
        raw_bucket=args.raw_bucket,
        game_name=args.game_name,
        tag_line=args.tag_line,
        match_count=args.count,
        secret_id=args.secret_id,
    )
    uploaded_objects = ingest(config)
    print(f"Uploaded {len(uploaded_objects)} raw match file(s):")
    for object_name in uploaded_objects:
        print(f"gs://{config.raw_bucket}/{object_name}")


if __name__ == "__main__":
    main()
