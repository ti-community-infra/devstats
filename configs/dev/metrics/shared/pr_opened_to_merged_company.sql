with prs as (
    select
        pr.created_at,
        pr.merged_at,
        CASE WHEN aa.company_name = 'PingCAP' THEN 'is-top-contributing-company'
             ELSE 'not-top-contributing-company'
        END company_category
    from
        gha_pull_requests pr
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
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
        CASE WHEN aa.company_name = 'PingCAP' THEN 'is-top-contributing-company'
             ELSE 'not-top-contributing-company'
        END company_category,
        pr.created_at,
        pr.merged_at as merged_at
    from
        gha_repos r,
        gha_pull_requests pr
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
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
-- All Repository, All is-top-contributing-company Contributors.
union
(
    select
        'open2merge_company;All_is-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs
    where
        company_category = 'is-top-contributing-company'
)
-- Repository, All not-top-contributing-company Contributors.
union
(
    select
        'open2merge_company;All_not-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs
    where
        company_category = 'not-top-contributing-company'
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
-- Repository Group, All is-top-contributing-company Contributors.
union
(
    select
        'open2merge_company;' || repo_group || '_is-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs_groups
    where
        company_category = 'is-top-contributing-company'
    group by
        repo_group
    order by
        open_to_merge_median desc,
        name
)
-- Repository Group, All not-top-contributing-company Contributors.
union
(
    select
        'open2merge_company;' || repo_group || '_not-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by open_to_merge asc) as open_to_merge_15_percentile,
        percentile_disc(0.5) within group (order by open_to_merge asc) as open_to_merge_median,
        percentile_disc(0.85) within group (order by open_to_merge asc) as open_to_merge_85_percentile
    from
        tdiffs_groups
    where
        company_category = 'not-top-contributing-company'
    group by
        repo_group
    order by
        open_to_merge_median desc,
        name
)
;