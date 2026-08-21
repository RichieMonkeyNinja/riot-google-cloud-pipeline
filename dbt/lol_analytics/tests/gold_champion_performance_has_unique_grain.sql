-- Gold grain: one row per date, patch, and champion.
select
    game_date,
    game_version,
    champion_id,
    count(*) as duplicate_rows
from {{ ref('gold_champion_performance') }}
group by 1, 2, 3
having count(*) > 1
