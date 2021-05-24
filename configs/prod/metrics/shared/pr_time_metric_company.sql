with prs_latest as (
    select
        sub.id,
        sub.event_id,
        sub.user_id,
        sub.created_at,
        sub.merged_at,
        sub.dup_repo_id,
        sub.dup_repo_name
    from (
        select
            id,
            event_id,
            user_id,
            created_at,
            merged_at,
            dup_repo_id,
            dup_repo_name,
            row_number() over (partition by id order by updated_at desc, event_id desc) as rank
        from
            gha_pull_requests
        where
            created_at >= '{{from}}'
            and created_at < '{{to}}'
            and merged_at is not null
    ) sub
    where
        sub.rank = 1
), prs as (
    select
        ipr.issue_id,
        pr.created_at,
        pr.merged_at,
        CASE WHEN aa.company_name = 'PingCAP' THEN 'is-top-contributing-company'
             ELSE 'not-top-contributing-company'
        END company_category
    from
        gha_issues_pull_requests ipr,
        prs_latest pr
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    where
        pr.id = ipr.pull_request_id
), prs_groups as (
    select
        r.repo_group,
        ipr.issue_id,
        pr.created_at,
        pr.merged_at,
        CASE WHEN aa.company_name = 'PingCAP' THEN 'is-top-contributing-company'
             ELSE 'not-top-contributing-company'
        END company_category
    from
        gha_issues_pull_requests ipr,
        gha_repos r,
        prs_latest pr
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    where
        r.id = ipr.repo_id
        and r.name = ipr.repo_name
        and r.id = pr.dup_repo_id
        and r.name = pr.dup_repo_name
        and r.repo_group is not null
        and pr.id = ipr.pull_request_id
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
-- All repositories and all contributors.
select
    'pr_time_metric_company;All_All;med,p85' as name,
    greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
    greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
from
    tdiffs
-- All repositories and is-top-contributing-company contributors.
union
(
    select
        'pr_time_metric_company;All_is-top-contributing-company;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs
    where
        company_category = 'is-top-contributing-company'
)
-- All repositories and not-top-contributing-company contributors.
union
(
    select
        'pr_time_metric_company;All_not-top-contributing-company;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs
    where
        company_category = 'not-top-contributing-company'
)
-- Repository groups and all contributors.
union
(
    select
        'pr_time_metric_company;' || repo_group || '_All;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs_groups
    group by
        repo_group
    order by
        name asc
)
-- Repository groups and is-top-contributing-company contributors.
union
(
    select
        'pr_time_metric_company;' || repo_group || '_is-top-contributing-company;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs_groups
    where
        company_category = 'is-top-contributing-company'
    group by
        repo_group
    order by
        name asc
)
-- Repository groups and not-top-contributing-company contributors.
union
(
    select
        'pr_time_metric_company;' || repo_group || '_not-top-contributing-company;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs_groups
    where
        company_category = 'not-top-contributing-company'
    group by
        repo_group
    order by
        name asc
)
;
