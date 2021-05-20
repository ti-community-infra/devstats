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
        CASE WHEN aa.company_name = 'PingCAP' THEN 'Internal'
             ELSE 'External'
        END company_category
    from
        gha_issues_pull_requests ipr,
        prs_latest pr
    left join
        gha_actors_affiliations aa on aa.actor_id = pr.user_id
    where
        pr.id = ipr.pull_request_id
), prs_groups as (
    select
        r.repo_group,
        ipr.issue_id,
        pr.created_at,
        pr.merged_at,
        CASE WHEN aa.company_name = 'PingCAP' THEN 'Internal'
             ELSE 'External'
        END company_category
    from
        gha_issues_pull_requests ipr,
        gha_repos r,
        prs_latest pr
    left join
        gha_actors_affiliations aa on aa.actor_id = pr.user_id
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
-- All repositories and internal contributors.
union
(
    select
        'pr_time_metric_company;All_Internal;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs
    where
        company_category = 'Internal'
)
-- All repositories and external contributors.
union
(
    select
        'pr_time_metric_company;All_External;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs
    where
        company_category = 'External'
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
-- Repository groups and internal contributors.
union
(
    select
        'pr_time_metric_company;' || repo_group || '_Internal;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs_groups
    where
        company_category = 'Internal'
    group by
        repo_group
    order by
        name asc
)
-- Repository groups and external contributors.
union
(
    select
        'pr_time_metric_company;' || repo_group || '_External;med,p85' as name,
        greatest(percentile_disc(0.5) within group (order by open_to_merge asc), 0) as m_o2m,
        greatest(percentile_disc(0.85) within group (order by open_to_merge asc), 0) as pc_o2m
    from
        tdiffs_groups
    where
        company_category = 'External'
    group by
        repo_group
    order by
        name asc
)
;
