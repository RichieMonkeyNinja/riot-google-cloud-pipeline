"""Regression tests for the bronze-to-silver validation rules."""

from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest
from pyspark.sql import SparkSession

from src.transform_matches import TransformResult, build_silver


FIXTURE_PATH = Path(__file__).parent / "fixtures" / "match_NA1_0000000001.json"


@pytest.fixture(scope="session")
def spark() -> SparkSession:
    """Start one small Spark engine for all tests, then stop it cleanly."""
    session = SparkSession.builder.master("local[1]").appName(
        "bronze-to-silver-tests"
    ).getOrCreate()
    yield session
    session.stop()


@pytest.fixture
def valid_match() -> dict:
    """Return a fresh copy so each test can safely damage its own input."""
    with FIXTURE_PATH.open(encoding="utf-8") as fixture:
        return json.load(fixture)


def result_for(spark: SparkSession, match: dict) -> TransformResult:
    """Create a Spark JSON DataFrame from one deliberately chosen payload."""
    raw = spark.read.json(spark.sparkContext.parallelize([json.dumps(match)]))
    return build_silver(raw)


def test_valid_match_creates_ten_silver_participants_and_metrics(
    spark: SparkSession, valid_match: dict
) -> None:
    result = result_for(spark, valid_match)

    assert result.matches.count() == 1
    assert result.participants.count() == 10
    first_player = result.participants.filter("participant_id = 1").first()
    assert first_player.game_version == "16.1.1"
    assert first_player.kda == pytest.approx(3.0)
    assert first_player.cs == 184
    assert first_player.damage_per_minute == pytest.approx(613.75)


@pytest.mark.parametrize(
    "broken_field",
    ["match_id", "puuid", "champion_name"],
)
def test_missing_required_values_are_rejected(
    spark: SparkSession, valid_match: dict, broken_field: str
) -> None:
    broken_match = copy.deepcopy(valid_match)
    if broken_field == "match_id":
        broken_match["metadata"]["matchId"] = ""
    elif broken_field == "puuid":
        broken_match["info"]["participants"][0]["puuid"] = ""
    else:
        broken_match["info"]["participants"][0]["championName"] = ""

    result = result_for(spark, broken_match)

    assert result.matches.count() == 0
    assert result.participants.count() == 0


def test_negative_stat_rejects_player_and_incomplete_classic_match(
    spark: SparkSession, valid_match: dict
) -> None:
    broken_match = copy.deepcopy(valid_match)
    broken_match["info"]["participants"][0]["kills"] = -1
    result = result_for(spark, broken_match)

    assert result.rejected_participant_count == 1
    assert result.rejected_match_count == 1
    assert result.matches.count() == 0
    assert result.participants.count() == 0


def test_duplicate_player_is_kept_once(spark: SparkSession, valid_match: dict) -> None:
    duplicate_match = copy.deepcopy(valid_match)
    duplicate_match["info"]["participants"].append(
        copy.deepcopy(duplicate_match["info"]["participants"][0])
    )
    result = result_for(spark, duplicate_match)

    assert result.matches.count() == 1
    assert result.participants.count() == 10
