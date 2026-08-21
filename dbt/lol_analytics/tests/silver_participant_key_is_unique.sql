-- A silver player is uniquely identified by their participant number in a match.
-- dbt fails this test if this query returns even one row.
select
    match_id,
    participant_id,
    count(*) as duplicate_rows
from {{ source('silver', 'silver_participants') }}
group by 1, 2
having count(*) > 1
