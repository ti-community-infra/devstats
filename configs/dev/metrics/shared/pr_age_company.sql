with prs as (
  select
    pr.id,
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
    pr.created_at >= '{{from}}'
    and pr.created_at < '{{to}}'
    and pr.event_id = (
      select i.event_id from gha_pull_requests i where i.id = pr.id order by i.updated_at desc limit 1
    )
    and (
      pr.closed_at is null
      or (
        pr.closed_at is not null
        and pr.merged_at is not null
      )
    )
), prs_groups as (
  select
    r.repo_group,
    pr.id,
    pr.created_at,
    pr.merged_at as merged_at,
    CASE WHEN aa.company_name = 'PingCAP' THEN 'Internal'
         ELSE 'External'
    END company_category
  from
    gha_repos r,
    gha_pull_requests pr
  left join
    gha_actors_affiliations aa on aa.actor_id = pr.user_id
  where
    r.id = pr.dup_repo_id
    and r.name = pr.dup_repo_name
    and r.repo_group is not null
    and pr.created_at >= '{{from}}'
    and pr.created_at < '{{to}}'
    and pr.event_id = (
      select i.event_id from gha_pull_requests i where i.id = pr.id order by i.updated_at desc limit 1
    )
    and (
      pr.closed_at is null
      or (
        pr.closed_at is not null
        and pr.merged_at is not null
      )
    )
), tdiffs as (
  select
     id,
     company_category,
     extract(epoch from coalesce(merged_at - created_at, now() - created_at)) / 3600 as age
  from
    prs
), tdiffs_groups as (
  select
    repo_group,
    id,
    company_category,
    extract(epoch from coalesce(merged_at - created_at, now() - created_at)) / 3600 as age
  from
    prs_groups
)
-- All repositories and all contributors.
select
    'pr_age_company;All_All;n,m' as name,
    round(count(distinct id) / {{n}}, 2) as num,
    percentile_disc(0.5) within group (order by age asc) as age_median
from
  tdiffs
-- All repositories and internal contributors.
union
(
    select
        'pr_age_company;All_Internal;n,m' as name,
        round(count(distinct id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by age asc) as age_median
    from
        tdiffs
    where
        company_category = 'Internal'
)
-- All repositories and external contributors.
union
(
    select
        'pr_age_company;All_External;n,m' as name,
        round(count(distinct id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by age asc) as age_median
    from
        tdiffs
    where
        company_category = 'External'
)
-- Repository groups and all contributors.
union
(
    select
        'pr_age_company;' || repo_group || '_All;n,m' as name,
        round(count(distinct id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by age asc) as age_median
    from
        tdiffs_groups
    group by
        repo_group
    order by
        num desc,
        name asc
)
-- Repository groups and internal contributors.
union
(
    select
        'pr_age_company;' || repo_group || '_Internal;n,m' as name,
        round(count(distinct id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by age asc) as age_median
    from
        tdiffs_groups
    where
        company_category = 'Internal'
    group by
        repo_group
    order by
        num desc,
        name asc
)
-- Repository groups and external contributors.
union
(
    select
        'pr_age_company;' || repo_group || '_External;n,m' as name,
        round(count(distinct id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by age asc) as age_median
    from
        tdiffs_groups
    where
        company_category = 'External'
    group by
        repo_group
    order by
        num desc,
        name asc
)
;
