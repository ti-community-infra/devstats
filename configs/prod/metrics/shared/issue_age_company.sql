with issues as (
    select
        i.id,
        r.repo_group,
        i.created_at,
        i.closed_at as closed_at,
        case
            when aa.company_name = 'PingCAP' then 'is-top-contributing-company'
            else 'not-top-contributing-company'
        end company_category
    from
        gha_repos r,
        gha_issues i
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = i.user_id
        and aa.dt_from <= i.created_at
        and aa.dt_to > i.created_at
    where
        i.is_pull_request = false
        and i.closed_at is not null
        and r.name = i.dup_repo_name
        and r.id = i.dup_repo_id
        and i.created_at >= '{{from}}'
        and i.created_at < '{{to}}'
        and i.event_id = (
            select n.event_id from gha_issues n where n.id = i.id order by n.updated_at desc limit 1
        )
), tdiffs as (
    select
        id,
        repo_group,
        company_category,
        extract(epoch from closed_at - created_at) / 3600 as age
    from
        issues
)
-- All repositories and all contributors.
select
    'issue_age_company;All_All;n,m' as name,
    round(count(distinct t.id) / {{n}}, 2) as num,
    percentile_disc(0.5) within group (order by t.age asc) as age_median
from
    tdiffs t
-- All repositories and is-top-contributing-company contributors.
union
(
    select
        'issue_age_company;All_is-top-contributing-company;n,m' as name,
        round(count(distinct t.id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by t.age asc) as age_median
    from
        tdiffs t
    where
        company_category = 'is-top-contributing-company'
)
-- All repositories and not-top-contributing-company contributors.
union
(
    select
        'issue_age_company;All_not-top-contributing-company;n,m' as name,
        round(count(distinct t.id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by t.age asc) as age_median
    from
        tdiffs t
    where
        company_category = 'not-top-contributing-company'
)
-- Repository groups and all contributors.
union
(
    select
        'issue_age_company;' || t.repo_group || '_All;n,m' as name,
        round(count(distinct t.id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by t.age asc) as age_median
    from
        tdiffs t
    where
        t.repo_group is not null
    group by
        t.repo_group
)
-- Repository groups and is-top-contributing-company contributors.
union
(
    select
        'issue_age_company;' || t.repo_group || '_is-top-contributing-company;n,m' as name,
        round(count(distinct t.id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by t.age asc) as age_median
    from
        tdiffs t
    where
        t.repo_group is not null
        and company_category = 'is-top-contributing-company'
    group by
        t.repo_group
)
-- Repository groups and not-top-contributing-company contributors.
union
(
    select
        'issue_age_company;' || t.repo_group || '_not-top-contributing-company;n,m' as name,
        round(count(distinct t.id) / {{n}}, 2) as num,
        percentile_disc(0.5) within group (order by t.age asc) as age_median
    from
        tdiffs t
    where
        t.repo_group is not null
        and company_category = 'not-top-contributing-company'
    group by
        t.repo_group
)
;
