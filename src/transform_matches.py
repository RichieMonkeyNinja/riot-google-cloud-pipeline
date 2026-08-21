"""Turn raw Riot Match-V5 JSON (bronze) into validated silver Parquet tables."""

from __future__ import annotations

import argparse
from dataclasses import dataclass

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F


@dataclass(frozen=True)
class TransformResult:
    """The accepted silver tables and counts needed for a readable run summary."""

    matches: DataFrame
    participants: DataFrame
    raw_match_count: int
    raw_participant_count: int
    rejected_participant_count: int
    rejected_match_count: int


def parse_args() -> argparse.Namespace:
    """Read the bronze JSON location and the silver destination from the CLI."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        required=True,
        help="One JSON file, a directory of JSON files, or a gs:// bronze-data path.",
    )
    parser.add_argument(
        "--output",
        default="data/silver",
        help="Directory or gs:// path for silver Parquet output (default: data/silver).",
    )
    parser.add_argument(
        "--mode",
        choices=("error", "overwrite"),
        default="error",
        help="What to do if silver output already exists (default: error).",
    )
    return parser.parse_args()


def flattened_matches(raw_matches: DataFrame) -> DataFrame:
    """Flatten top-level match fields and remove records without a match ID."""
    return (
        raw_matches.select(
            F.trim(F.col("metadata.matchId")).alias("match_id"),
            F.col("info.gameId").cast("long").alias("game_id"),
            F.to_timestamp(F.from_unixtime(F.col("info.gameCreation") / 1000)).alias(
                "game_created_at"
            ),
            F.col("info.gameDuration").cast("long").alias("game_duration_seconds"),
            F.col("info.gameMode").alias("game_mode"),
            F.col("info.gameType").alias("game_type"),
            F.col("info.gameVersion").alias("game_version"),
            F.col("info.queueId").cast("int").alias("queue_id"),
        )
        .filter(F.col("match_id").isNotNull() & (F.col("match_id") != ""))
        .filter(F.col("game_duration_seconds") > 0)
        .dropDuplicates(["match_id"])
        .withColumn("game_date", F.to_date("game_created_at"))
    )


def flattened_participants(raw_matches: DataFrame) -> DataFrame:
    """Flatten nested players, retaining only rows that pass row-level checks."""
    flattened = raw_matches.select(
        F.trim(F.col("metadata.matchId")).alias("match_id"),
        F.col("info.gameDuration").cast("long").alias("game_duration_seconds"),
        F.to_date(F.to_timestamp(F.from_unixtime(F.col("info.gameCreation") / 1000))).alias(
            "game_date"
        ),
        F.col("info.gameVersion").alias("game_version"),
        F.explode("info.participants").alias("player"),
    ).select(
        "match_id",
        "game_date",
        "game_version",
        "game_duration_seconds",
        F.col("player.participantId").cast("int").alias("participant_id"),
        F.trim(F.col("player.puuid")).alias("puuid"),
        F.col("player.summonerName").alias("summoner_name"),
        F.col("player.teamId").cast("int").alias("team_id"),
        F.col("player.teamPosition").alias("team_position"),
        F.col("player.championId").cast("int").alias("champion_id"),
        F.trim(F.col("player.championName")).alias("champion_name"),
        F.col("player.win").cast("boolean").alias("won"),
        F.col("player.kills").cast("int").alias("kills"),
        F.col("player.deaths").cast("int").alias("deaths"),
        F.col("player.assists").cast("int").alias("assists"),
        F.col("player.goldEarned").cast("int").alias("gold_earned"),
        F.col("player.totalMinionsKilled").cast("int").alias("lane_minions_killed"),
        F.col("player.neutralMinionsKilled")
        .cast("int")
        .alias("neutral_minions_killed"),
        F.col("player.totalDamageDealtToChampions")
        .cast("long")
        .alias("damage_to_champions"),
        F.col("player.visionScore").cast("int").alias("vision_score"),
    )
    required_values_present = (
        F.col("match_id").isNotNull()
        & (F.col("match_id") != "")
        & F.col("puuid").isNotNull()
        & (F.col("puuid") != "")
        & F.col("champion_name").isNotNull()
        & (F.col("champion_name") != "")
    )
    non_negative_combat_stats = (
        (F.col("kills") >= 0) & (F.col("deaths") >= 0) & (F.col("assists") >= 0)
    )
    valid_rows = flattened.filter(required_values_present & non_negative_combat_stats)

    # A duplicate source file can repeat the same player/match. Keep one row.
    duplicate_window = Window.partitionBy("match_id", "participant_id").orderBy(
        F.col("puuid").asc()
    )
    return (
        valid_rows.withColumn("duplicate_rank", F.row_number().over(duplicate_window))
        .filter(F.col("duplicate_rank") == 1)
        .drop("duplicate_rank")
        .withColumn(
            "kda",
            F.round(
                F.when(F.col("deaths") == 0, F.col("kills") + F.col("assists")).otherwise(
                    (F.col("kills") + F.col("assists")) / F.col("deaths")
                ),
                2,
            ),
        )
        .withColumn(
            "cs", F.col("lane_minions_killed") + F.col("neutral_minions_killed")
        )
        .withColumn(
            "damage_per_minute",
            F.round(F.col("damage_to_champions") * 60 / F.col("game_duration_seconds"), 2),
        )
        .drop("game_duration_seconds")
    )


def build_silver(raw_matches: DataFrame) -> TransformResult:
    """Apply row and match validation, returning only trustworthy silver rows.

    A `CLASSIC` match is our definition of a normal 5v5 match. It must have
    exactly ten valid participants; otherwise the whole match is rejected.
    """
    raw_match_count = raw_matches.count()
    raw_participant_count = raw_matches.select(F.explode("info.participants")).count()
    matches = flattened_matches(raw_matches)
    participants = flattened_participants(raw_matches)
    rejected_participant_count = raw_participant_count - participants.count()

    participant_counts = participants.groupBy("match_id").agg(
        F.count("*").alias("participant_count")
    )
    checked_matches = matches.join(participant_counts, "match_id", "left")
    valid_matches = checked_matches.filter(
        (F.col("game_mode") != "CLASSIC")
        | (F.col("participant_count") == 10)
    ).drop("participant_count")
    rejected_match_count = matches.count() - valid_matches.count()
    valid_participants = participants.join(valid_matches.select("match_id"), "match_id")
    return TransformResult(
        matches=valid_matches,
        participants=valid_participants,
        raw_match_count=raw_match_count,
        raw_participant_count=raw_participant_count,
        rejected_participant_count=rejected_participant_count,
        rejected_match_count=rejected_match_count,
    )


def write_silver(frame: DataFrame, path: str, mode: str) -> None:
    """Write a silver table as date-partitioned Parquet."""
    writer_mode = "errorifexists" if mode == "error" else mode
    frame.write.mode(writer_mode).partitionBy("game_date").parquet(path)


def main() -> None:
    """Read bronze JSON, validate it, and write the two silver tables."""
    args = parse_args()
    spark = SparkSession.builder.appName("lol-bronze-to-silver").getOrCreate()
    try:
        raw_matches = spark.read.option("multiLine", "true").json(args.input)
        result = build_silver(raw_matches)
        silver_match_count = result.matches.count()
        silver_participant_count = result.participants.count()
        if silver_match_count == 0:
            raise ValueError("No valid silver matches found. Check rejected-row rules and input.")

        output_root = args.output.rstrip("/")
        write_silver(result.matches, f"{output_root}/silver_matches", args.mode)
        write_silver(result.participants, f"{output_root}/silver_participants", args.mode)
        print(
            "Bronze-to-silver summary: "
            f"raw_matches={result.raw_match_count}, "
            f"raw_participants={result.raw_participant_count}, "
            f"rejected_participants={result.rejected_participant_count}, "
            f"rejected_matches={result.rejected_match_count}, "
            f"silver_matches={silver_match_count}, "
            f"silver_participants={silver_participant_count}."
        )
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
