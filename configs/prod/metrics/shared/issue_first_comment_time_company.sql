with issues as (
    select
        distinct id,
        min(created_at) over issues_timeline as created_at,
        first_value(user_id) over issues_timeline as user_id,
        case
             when aa.company_name = 'PingCAP' then 'is-top-contributing-company'
             else 'not-top-contributing-company'
        end company_category
    from
        gha_issues i
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = i.user_id
        and aa.dt_from <= i.created_at
        and aa.dt_to > i.created_at
    where
        is_pull_request = false
        and created_at >= '{{from}}'
        and created_at < '{{to}}'
    window
        issues_timeline as (
            partition by
                id
            order by
                updated_at,
                event_id
            range between unbounded preceding
            and current row
        )
), tdiffs as (
    select
       extract(epoch from i2.updated_at - i.created_at) / 3600 as diff,
       r.repo_group as repo_group,
       company_category
    from
        issues i,
        gha_repos r,
        gha_issues i2
    where
        i.id = i2.id
        and r.name = i2.dup_repo_name
        and r.id = i2.dup_repo_id
        and (lower(i2.dup_actor_login) {{exclude_bots}})
        -- Select first non-author comment.
        and i2.event_id in (
            select
               event_id
            from
                gha_issues sub
            where
                sub.dup_actor_id != i.user_id
                and sub.id = i.id
                and sub.updated_at > i.created_at + '30 seconds'::interval
                and sub.dup_type = 'IssueCommentEvent'
            order by
                sub.updated_at asc
            limit 1
        )
)
-- All repositories and all contributors.
select
    'issue_first_comment_company;All_All;p15,med,p85' as name,
    percentile_disc(0.15) within group (order by diff asc) as first_comment_15_percentile,
    percentile_disc(0.5) within group (order by diff asc) as first_comment_median,
    percentile_disc(0.85) within group (order by diff asc) as first_comment_85_percentile
from
    tdiffs
-- All repositories and is-top-contributing-company contributors.
union
(
    select
        'issue_first_comment_company;All_is-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by diff asc) as first_comment_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as first_comment_median,
        percentile_disc(0.85) within group (order by diff asc) as first_comment_85_percentile
    from
        tdiffs
    where
        company_category = 'is-top-contributing-company'
)
-- All repositories and not-top-contributing-company contributors.
union
(
    select
        'issue_first_comment_company;All_not-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by diff asc) as first_comment_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as first_comment_median,
        percentile_disc(0.85) within group (order by diff asc) as first_comment_85_percentile
    from
        tdiffs
    where
        company_category = 'not-top-contributing-company'
)
-- Repository groups and all contributors.
union
(
    select
        'issue_first_comment_company;' || repo_group || '_All;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by diff asc) as first_comment_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as first_comment_median,
        percentile_disc(0.85) within group (order by diff asc) as first_comment_85_percentile
    from
        tdiffs
    where
        repo_group is not null
    group by
        repo_group
    order by
        first_comment_median desc,
        name asc
)
-- Repository groups and is-top-contributing-company contributors.
union
(
    select
        'issue_first_comment_company;' || repo_group || '_is-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by diff asc) as first_comment_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as first_comment_median,
        percentile_disc(0.85) within group (order by diff asc) as first_comment_85_percentile
    from
        tdiffs
    where
        repo_group is not null
        and company_category = 'is-top-contributing-company'
    group by
        repo_group
    order by
        first_comment_median desc,
        name asc
)
-- Repository groups and not-top-contributing-company contributors.
union
(
    select
        'issue_first_comment_company;' || repo_group || '_not-top-contributing-company;p15,med,p85' as name,
        percentile_disc(0.15) within group (order by diff asc) as first_comment_15_percentile,
        percentile_disc(0.5) within group (order by diff asc) as first_comment_median,
        percentile_disc(0.85) within group (order by diff asc) as first_comment_85_percentile
    from
        tdiffs
    where
        repo_group is not null
        and company_category = 'not-top-contributing-company'
    group by
        repo_group
    order by
        first_comment_median desc,
        name asc
)
;
