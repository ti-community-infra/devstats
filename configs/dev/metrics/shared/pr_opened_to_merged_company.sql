with prs as (
  select
     pr.created_at,
     pr.merged_at,
     CASE WHEN aa.company_name = 'PingCAP' THEN 'Internal'
          ELSE 'External'
     END company_category
  from
    gha_pull_requests pr
  left join
    gha_actors_affiliations aa on aa.actor_id = pr.user_id
  where
    pr.merged_at is not null
    and pr.created_at >= '{{from}}'
    and pr.created_at < '{{to}}'
    -- Select the latest pr event.
    and pr.event_id = (
      select i.event_id from gha_pull_requests i where i.id = pr.id order by i.updated_at desc limit 1
    )
), prs_groups as (
  select
    r.repo_group,
    CASE WHEN aa.company_name = 'PingCAP' THEN 'Internal'
         ELSE 'External'
    END company_category,
    pr.created_at,
    pr.merged_at as merged_at
  from
    gha_repos r,
    gha_pull_requests pr
  left join
    gha_actors_affiliations aa on aa.actor_id = pr.user_id
  where
    r.id = pr.dup_repo_id
    and r.name = pr.dup_repo_name
    and r.repo_group is not null
    and pr.merged_at is not null
    and pr.created_at >= '{{from}}'
    and pr.created_at < '{{to}}'
    -- Select the latest pr event.
    and pr.event_id = (
      select i.event_id from gha_pull_requests i where i.id = pr.id order by i.updated_at desc limit 1
    )
), tdiffs as (
  select
     company_category,
     extract(epoch from merged_at - created_at) / 3600 as open_to_merge
  from
    prs
), tdiffs_groups as (
  select
     repo_group,
     company_category,
     extract(epoch from merged_at - created_at) / 3600 as open_to_merge
  from
    prs_groups
)
-- All Repository, All Contributors.
select
    'open2merge_company;All_All;p15,med,p85' as name,
    percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
    percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
    percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
from
    tdiffs
-- All Repository, All Internal Contributors.
union
(
    select
        'open2merge_company;All_Internal;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs
    where
        company_category = 'Internal'
)
-- Repository, All External Contributors.
union
(
    select
        'open2merge_company;All_External;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs
    where
        company_category = 'External'
)
-- Repository Group, All Contributors.
union
(
    select
        'open2merge_company;' || repo_group || '_All;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs_groups
    group by
        repo_group
    order by
        open_to_merge_median desc,
        name
)
-- Repository Group, All Internal Contributors.
union
(
    select
        'open2merge_company;' || repo_group || '_Internal;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs_groups
    where
        company_category = 'Internal'
    group by
        repo_group
    order by
        open_to_merge_median desc,
        name
)
-- Repository Group, All External Contributors.
union
(
    select
        'open2merge_company;' || repo_group || '_External;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs_groups
    where
        company_category = 'External'
    group by
        repo_group
    order by
        open_to_merge_median desc,
        name
)
;