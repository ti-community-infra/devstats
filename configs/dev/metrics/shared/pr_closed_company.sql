with closed_prs as (
    select
        pr.id id,
        lower(pr.dup_user_login) author_login,
        r.repo_group repo_group,
        case when aa.company_name = 'PingCAP' then 'is-top-contributing-company'
             else 'not-top-contributing-company'
        end company_category
    from
        gha_pull_requests pr
    left join
        gha_repos r
    on
        r.id = pr.dup_repo_id
        and r.name = pr.dup_repo_name
        and r.repo_group is not null
    left join
        gha_actors_affiliations aa
    on
        aa.actor_id = pr.user_id
        and aa.dt_from <= pr.created_at
        and aa.dt_to > pr.created_at
    where
        merged_at is null
        and closed_at is not null
        and closed_at >= '{{from}}'
        and closed_at < '{{to}}'
)
-- all repos, include bots

-- all repositories, include bots, all companies.
(
    select
        'pr_closed_company,all_include_bots_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
)
-- all repositories, include bots, is top contributing company.
union
(
    select
        'pr_closed_company,all_include_bots_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'is-top-contributing-company'
)

-- all repositories, include bots, not top contributing company.
union
(
    select
        'pr_closed_company,all_include_bots_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'not-top-contributing-company'
)

-- all repos, exclude bots

-- all repositories, exclude bots, all companies.
union
(
    select
        'pr_closed_company,all_exclude_bots_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        lower(author_login) {{exclude_bots}}
)
-- all repositories, exclude bots, is top contributing company.
union
(
    select
        'pr_closed_company,all_exclude_bots_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'is-top-contributing-company'
        and (lower(author_login) {{exclude_bots}})
)
-- all repositories, exclude bots, not top contributing company.
union
(
    select
        'pr_closed_company,all_exclude_bots_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'not-top-contributing-company'
        and (lower(author_login) {{exclude_bots}})
)

-- repo group, include bots

-- repository group, include bots, all companies.
union
(
    select
        'pr_closed_company,' || repo_group  || '_include_bots_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    group by
        repo_group
)
-- repository group, include bots, is top contributing company.
union
(
    select
        'pr_closed_company,' || repo_group  || '_include_bots_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'is-top-contributing-company'
    group by
        repo_group
)

-- repository group, include bots, not top contributing company.
union
(
    select
        'pr_closed_company,' || repo_group  || '_include_bots_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'not-top-contributing-company'
    group by
        repo_group
)

-- repo group, exclude bots

-- repository group, exclude bots, all companies.
union
(
    select
        'pr_closed_company,' || repo_group  || '_exclude_bots_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        lower(author_login) {{exclude_bots}}
    group by
        repo_group
)
-- repository group, exclude bots, is top contributing company.
union
(
    select
        'pr_closed_company,' || repo_group  || '_exclude_bots_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'is-top-contributing-company'
        and (lower(author_login) {{exclude_bots}})
    group by
        repo_group
)
-- repository group, exclude bots, not top contributing company.
union
(
    select
        'pr_closed_company,' || repo_group  || '_exclude_bots_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        closed_prs
    where
        company_category = 'not-top-contributing-company'
        and (lower(author_login) {{exclude_bots}})
    group by
        repo_group
)