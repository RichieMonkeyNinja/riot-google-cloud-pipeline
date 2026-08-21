-- A win rate is a proportion, and count metrics cannot be zero or negative.
select *
from {{ ref('gold_champion_performance') }}
where win_rate < 0
   or win_rate > 1
   or player_games <= 0
   or matches_played <= 0
   or wins < 0
   or losses < 0
