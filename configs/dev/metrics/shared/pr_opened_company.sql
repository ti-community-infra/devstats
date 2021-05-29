with opened_prs as (
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
        pr.created_at >= '{{from}}'
        and pr.created_at < '{{to}}'
        and pr.event_id = (
            select i.event_id from gha_pull_requests i where i.id = pr.id order by i.updated_at desc limit 1
        )
)
-- all repos, include bots

-- all repositories, include bots, all companies.
(
    select
        'pr_opened_company,all_repo_include_bot_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
)
-- all repositories, include bots, is top contributing company.
union
(
    select
        'pr_opened_company,all_repo_include_bot_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        company_category = 'is-top-contributing-company'
)

-- all repositories, include bots, not top contributing company.
union
(
    select
        'pr_opened_company,all_repo_include_bot_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        company_category = 'not-top-contributing-company'
)

-- all repos, exclude bots

-- all repositories, exclude bots, all companies.
union
(
    select
        'pr_opened_company,all_repo_exclude_bots_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        author_login {{exclude_bots}}
)
-- all repositories, exclude bots, is top contributing company.
union
(
    select
        'pr_opened_company,all_repo_exclude_bots_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        company_category = 'is-top-contributing-company'
        and author_login {{exclude_bots}}
)
-- all repositories, exclude bots, not top contributing company.
union
(
    select
        'pr_opened_company,all_repo_exclude_bots_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        company_category = 'not-top-contributing-company'
        and author_login {{exclude_bots}}
)

-- repo group, include bots

-- repository group, include bots, all companies.
union
(
    select
        'pr_opened_company,' || repo_group  || '_include_bot_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    group by
        repo_group
)
-- repository group, include bots, is top contributing company.
union
(
    select
        'pr_opened_company,' || repo_group  || '_include_bot_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        company_category = 'is-top-contributing-company'
    group by
        repo_group
)

-- repository group, include bots, not top contributing company.
union
(
    select
        'pr_opened_company,' || repo_group  || '_include_bot_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
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
        'pr_opened_company,' || repo_group  || '_exclude_bot_all_company' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        author_login {{exclude_bots}}
    group by
        repo_group
)
-- repository group, exclude bots, is top contributing company.
union
(
    select
        'pr_opened_company,' || repo_group  || '_exclude_bot_is_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        company_category = 'is-top-contributing-company'
        and author_login {{exclude_bots}}
    group by
        repo_group
)
-- repository group, exclude bots, not top contributing company.
union
(
    select
        'pr_opened_company,' || repo_group  || '_exclude_bot_not_top' as series,
        round(count(distinct id) / {{n}}, 2) as count
    from
        opened_prs
    where
        company_category = 'not-top-contributing-company'
        and author_login {{exclude_bots}}
    group by
        repo_group
)