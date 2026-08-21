{{
  config(
    materialized='table',
    description='Daily champion performance metrics calculated from validated silver participants.'
  )
}}

with silver_participants as (
    select
        game_date,
        game_version,
        match_id,
        champion_id,
        champion_name,
        won,
        kda,
        cs,
        damage_per_minute
    from {{ source('silver', 'silver_participants') }}
),

champion_performance as (
    select
        game_date,
        game_version,
        champion_id,
        champion_name,
        count(*) as player_games,
        count(distinct match_id) as matches_played,
        countif(won) as wins,
        countif(not won) as losses,
        round(safe_divide(countif(won), count(*)), 4) as win_rate,
        round(avg(kda), 2) as average_kda,
        round(avg(cs), 2) as average_cs,
        round(avg(damage_per_minute), 2) as average_damage_per_minute
    from silver_participants
    group by 1, 2, 3, 4
)

select * from champion_performance
